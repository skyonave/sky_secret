import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/github_credentials.dart';

part '_github_transport.dart';
part '../models/_github_models.dart';
part '../models/_github_response.dart';
part '_git_blob.dart';
part '_github_value.dart';

class GitHubApi {
  final GitHubTransport transport;
  DateTime? _notBefore;
  static const apiVersion = '2026-03-10';
  static const appId = 'secret-manager-vault';
  static const marker = '{"appId":"secret-manager-vault","version":1}';
  static const maxVaultBytes = 72 * 1024 * 1024;

  GitHubApi({GitHubTransport? transport}) : transport = transport ?? GitHubHttp.request;

  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Object? body,
    int limit = 2 * 1024 * 1024,
  }) async {
    if (_notBefore != null && DateTime.now().isBefore(_notBefore!)) {
      throw GitHubFailure(
        GitHubProblem.denied,
        retryAfter: _notBefore!.difference(DateTime.now()),
      );
    }
    final uri = Uri.parse('https://api.github.com$path');
    if (!path.startsWith('/') || uri.userInfo.isNotEmpty || uri.host != 'api.github.com') {
      throw const GitHubFailure(GitHubProblem.configuration);
    }
    final response = await transport(
      method,
      uri,
      {
        'Accept': 'application/json',
        'User-Agent': 'SkySecret',
        'X-GitHub-Api-Version': apiVersion,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body,
      limit,
    );
    if (response.status >= 200 && response.status < 300) return response.body;
    Duration? retry;
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (seconds != null) retry = Duration(seconds: max(1, seconds));
    if (seconds == null && response.headers['retry-after'] != null) {
      try {
        retry = HttpDate.parse(response.headers['retry-after']!).difference(DateTime.now());
        if (retry.isNegative) retry = const Duration(seconds: 1);
      } on FormatException catch (_) {}
    }
    if (response.headers['x-ratelimit-remaining'] == '0' && reset != null) {
      retry = Duration(
        seconds: (reset - DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1).clamp(1, 1 << 32),
      );
    }
    if (response.status == 403 || response.status == 429) {
      retry ??= const Duration(minutes: 1);
    }
    if (retry != null) _notBefore = DateTime.now().add(retry);
    throw GitHubFailure(
      switch (response.status) {
        401 => GitHubProblem.authorization,
        403 || 429 => GitHubProblem.denied,
        404 => GitHubProblem.missing,
        409 || 422 => GitHubProblem.conflict,
        >= 500 => GitHubProblem.network,
        _ => GitHubProblem.format,
      },
      retryAfter: retry ?? (response.status == 429 ? const Duration(minutes: 1) : null),
    );
  }

  Future<GitHubUser> user(String token) async =>
      GitHubUser.fromJson(GitHubValue.object(await request('GET', '/user', token: token)));

  Future<GitHubRepository> repository(
    String token,
    int id,
    int userId,
  ) async {
    final repo = GitHubRepository.fromJson(
      GitHubValue.object(await request('GET', '/repositories/$id', token: token)),
    );
    if (repo.id != id) throw const GitHubFailure(GitHubProblem.format);
    repo.validate(userId);
    return repo;
  }

  Future<GitHubRepository> repositoryByAddress(
    String token,
    GitHubRepositoryAddress address,
    int userId,
  ) async {
    final repo = GitHubRepository.fromJson(
      GitHubValue.object(await request('GET', address.route, token: token)),
    );
    repo.validate(userId);
    return repo;
  }

  static void validateMarker(List<int> bytes) {
    try {
      if (bytes.length > 4096) throw const FormatException();
      final json = GitHubValue.object(jsonDecode(utf8.decode(bytes)));
      if (json['appId'] != appId || json['version'] != 1) {
        throw const FormatException();
      }
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.format);
    }
  }

  Future<Uint8List> blob(
    String token,
    GitHubRepository repo,
    String hash, {
    int limit = maxVaultBytes,
  }) async {
    final response = GitHubValue.object(
      await request(
        'GET',
        '${repo.route}/git/blobs/${GitHubValue.sha(hash)}',
        token: token,
        limit: (limit * 1.5).ceil() + 8192,
      ),
    );
    if (response['encoding'] != 'base64' ||
        response['size'] is! int ||
        (response['size'] as int) < 0 ||
        (response['size'] as int) > limit ||
        response['content'] is! String) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(
        (response['content'] as String).replaceAll('\n', ''),
      );
    } catch (_) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    if (bytes.length != response['size'] || bytes.length > limit || await GitBlob.hash(bytes) != hash) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return bytes;
  }

  Future<RemoteSnapshot> snapshot(
    String token,
    GitHubRepository repo, {
    bool initializing = false,
  }) async {
    final ref = GitHubValue.object(
      await request(
        'GET',
        '${repo.route}/git/ref/heads/${Uri.encodeComponent(repo.branch)}',
        token: token,
      ),
    );
    final commit = GitHubValue.sha(GitHubValue.object(ref['object'])['sha']);
    final detail = GitHubValue.object(
      await request('GET', '${repo.route}/git/commits/$commit', token: token),
    );
    final tree = GitHubValue.sha(GitHubValue.object(detail['tree'])['sha']);
    final root = await _tree(token, repo, tree);
    final markerEntries = root.where((e) => e['path'] == 'vault.json').toList();
    if (markerEntries.isEmpty && initializing) {
      if (root.any(
        (e) => e['path'] != 'README.md' || e['type'] != 'blob' || e['mode'] != '100644',
      )) {
        throw const GitHubFailure(GitHubProblem.repositorySetup);
      }
    } else {
      if (markerEntries.length != 1 ||
          markerEntries.single['type'] != 'blob' ||
          markerEntries.single['mode'] != '100644') {
        throw const GitHubFailure(GitHubProblem.format);
      }
      validateMarker(
        await blob(token, repo, GitHubValue.sha(markerEntries.single['sha']), limit: 4096),
      );
    }
    final folders = root.where((e) => e['path'] == 'vaults').toList();
    final vaults = <String, RemoteVault>{};
    if (folders.isNotEmpty) {
      if (folders.length != 1 || folders.single['type'] != 'tree') {
        throw const GitHubFailure(GitHubProblem.format);
      }
      for (final entry in await _tree(
        token,
        repo,
        GitHubValue.sha(folders.single['sha']),
      )) {
        final path = GitHubValue.string(entry['path']);
        if (!RegExp(r'^[0-9a-f]{32}\.smv$').hasMatch(path) || entry['type'] != 'blob' || entry['mode'] != '100644') {
          throw const GitHubFailure(GitHubProblem.format);
        }
        final size = GitHubValue.positiveInt(entry['size']);
        if (size > maxVaultBytes) {
          throw const GitHubFailure(GitHubProblem.format);
        }
        final id = path.substring(0, 32);
        if (vaults.containsKey(id)) {
          throw const GitHubFailure(GitHubProblem.format);
        }
        vaults[id] = RemoteVault(id, GitHubValue.sha(entry['sha']), size);
      }
    }
    return RemoteSnapshot(commit, tree, vaults);
  }

  Future<List<Map<String, dynamic>>> _tree(
    String token,
    GitHubRepository repo,
    String hash,
  ) async {
    final json = GitHubValue.object(
      await request('GET', '${repo.route}/git/trees/$hash', token: token),
    );
    if (json['truncated'] != false || json['tree'] is! List) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return (json['tree'] as List).map(GitHubValue.object).toList();
  }

  Future<String> upload(
    String token,
    GitHubRepository repo,
    Uint8List bytes,
  ) async {
    if (bytes.length > maxVaultBytes) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    final result = GitHubValue.object(
      await request(
        'POST',
        '${repo.route}/git/blobs',
        token: token,
        body: {'content': base64.encode(bytes), 'encoding': 'base64'},
      ),
    );
    final hash = GitHubValue.sha(result['sha']);
    if (hash != await GitBlob.hash(bytes)) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return hash;
  }

  Future<String> commit(
    String token,
    GitHubRepository repo,
    RemoteSnapshot base,
    Map<String, String> updates,
  ) async {
    final tree = GitHubValue.object(
      await request(
        'POST',
        '${repo.route}/git/trees',
        token: token,
        body: {
          'base_tree': base.tree,
          'tree': [
            {
              'path': 'vault.json',
              'mode': '100644',
              'type': 'blob',
              'content': marker,
            },
            for (final entry in updates.entries)
              {
                'path': 'vaults/${GitHubValue.backupId(entry.key)}.smv',
                'mode': '100644',
                'type': 'blob',
                'sha': GitHubValue.sha(entry.value),
              },
          ],
        },
      ),
    );
    final commit = GitHubValue.object(
      await request(
        'POST',
        '${repo.route}/git/commits',
        token: token,
        body: {
          'message': 'Encrypted vault backup',
          'tree': GitHubValue.sha(tree['sha']),
          'parents': [base.commit],
        },
      ),
    );
    return GitHubValue.sha(commit['sha']);
  }

  Future<void> publish(
    String token,
    GitHubRepository repo,
    String commit,
  ) async {
    await request(
      'PATCH',
      '${repo.route}/git/refs/heads/${Uri.encodeComponent(repo.branch)}',
      token: token,
      body: {'sha': GitHubValue.sha(commit), 'force': false},
    );
  }
}
