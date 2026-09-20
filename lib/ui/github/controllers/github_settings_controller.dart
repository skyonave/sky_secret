import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/sync/github/controllers/github_backup.dart';
import '../../../core/sync/github/services/github_api.dart';

class GitHubSettingsController extends ChangeNotifier {
  final GitHubBackup? local;
  final Future<dynamic> Function(String, dynamic)? action;
  Map<String, dynamic> _state;
  Timer? _timer;
  bool _disposed = false;
  bool _requesting = false;

  GitHubSettingsController({this.local, this.action, Map<String, dynamic> initial = const {}}) : _state = initial {
    local?.addListener(notifyListeners);
    if (action != null) _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  static Map<String, dynamic> snapshot(GitHubBackup backup) => {
    'address': backup.repositoryAddress,
    'busy': backup.busy,
    'usable': backup.usable,
    'signedIn': backup.signedIn,
    'status': backup.status.name,
    'problem': backup.problem?.name,
    'recovery': backup.connectionNeedsRecovery,
    'login': backup.login,
    'repository': backup.repository?.label,
    'lastSync': backup.lastSync?.toIso8601String(),
    'conflicts': backup.conflicts.toList(),
    'remote': [
      for (final vault in backup.remoteVaults) {'id': vault.id, 'blob': vault.blob, 'size': vault.size},
    ],
  };

  Map<String, dynamic> get state => local == null ? _state : snapshot(local!);
  String get repositoryAddress => state['address'] as String? ?? '';
  bool get busy => _requesting || state['busy'] == true;
  bool get usable => state['usable'] == true;
  bool get signedIn => state['signedIn'] == true;
  bool get connectionNeedsRecovery => state['recovery'] == true;
  String? get login => state['login'] as String?;
  String? get repositoryLabel => state['repository'] as String?;
  BackupStatus get status => BackupStatus.values.byName(state['status'] as String? ?? 'disconnected');
  GitHubProblem? get problem =>
      state['problem'] == null ? null : GitHubProblem.values.byName(state['problem'] as String);
  DateTime? get lastSync => state['lastSync'] == null ? null : DateTime.parse(state['lastSync'] as String);
  List<dynamic> get conflicts => state['conflicts'] as List? ?? [];
  List<RemoteVault> get remoteVaults => [
    for (final item in state['remote'] as List? ?? [])
      RemoteVault(item['id'] as String, item['blob'] as String, item['size'] as int),
  ];

  Future<void> _refresh() async {
    if (_disposed || _requesting) return;
    try {
      final result = await action?.call('state', null);
      if (_disposed || result is! Map) return;
      _state = Map<String, dynamic>.from(result);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _request(String method, [dynamic arguments]) async {
    if (_requesting || _disposed) return;
    _requesting = true;
    notifyListeners();
    try {
      final result = await action?.call(method, arguments);
      if (!_disposed && result is Map) _state = Map<String, dynamic>.from(result);
    } finally {
      _requesting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> connectToken(String token, String repository, {bool initializeRepository = false}) async {
    if (local != null) {
      await local!.connectToken(token, repository, initializeRepository: initializeRepository);
      return;
    }
    await _request('connect', {'token': token, 'repository': repository, 'initialize': initializeRepository});
  }

  void cancelConnection() {
    if (local != null) local!.cancelConnection();
  }

  Future<void> resetDamagedConnection() async {
    if (local != null) {
      await local!.resetDamagedConnection();
    } else {
      await _request('recover');
    }
  }

  Future<void> discover() async {
    if (local != null) {
      await local!.discover();
    } else {
      await _request('discover');
    }
  }

  Future<void> sync() async {
    if (local != null) {
      await local!.sync();
    } else {
      await _request('backup');
    }
  }

  Future<void> keepBoth() async {
    if (local != null) {
      await local!.keepBoth();
    } else {
      await _request('keepBoth');
    }
  }

  Future<void> disconnect() async {
    if (local != null) {
      await local!.disconnect();
    } else {
      await _request('disconnect');
    }
  }

  Future<Uint8List?> download(RemoteVault vault) async => local?.download(vault);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    local?.removeListener(notifyListeners);
    super.dispose();
  }
}
