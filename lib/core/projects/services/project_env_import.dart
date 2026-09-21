import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../crypto/vault/models/project_environment.dart';
import 'project_dotenv.dart';

class ProjectEnvSource {
  final String root;
  final String path;
  final String name;
  final Uint8List _bytes;
  final ProjectEnvironment? environment;
  final bool invalid;
  bool _removed = false;
  ProjectEnvSource(this.root, this.path, this.name, this._bytes, this.environment, this.invalid);

  Future<bool> removeUnchanged({required bool Function() allowed}) async {
    if (!allowed() || environment == null) return false;
    if (_removed) return true;
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) return false;
    final resolved = await file.resolveSymbolicLinks();
    if (resolved != path || !resolved.startsWith('$root${Platform.pathSeparator}')) return false;
    if (await file.length() != _bytes.length) return false;
    final current = await file.readAsBytes();
    if (!allowed() || !listEquals(current, _bytes)) return false;
    await file.delete();
    _removed = true;
    return true;
  }

  void clear() => _bytes.fillRange(0, _bytes.length, 0);
}

abstract final class ProjectEnvImport {
  static const _ignored = {'.git', 'node_modules', '.dart_tool', 'build', 'dist', '.venv', 'venv', 'vendor'};

  static Future<List<ProjectEnvSource>> scan(Directory directory, {required bool Function() allowed}) async {
    final root = await directory.resolveSymbolicLinks();
    final pending = [Directory(root)];
    final result = <ProjectEnvSource>[];
    var inspected = 0;
    try {
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        await for (final entity in current.list(followLinks: false)) {
          if (!allowed()) throw const FileSystemException('Cancelled');
          if (++inspected > 20000 || result.length >= 128) throw const FileSystemException('Scan limit');
          final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
          if (entity is Directory) {
            if (!_ignored.contains(name.toLowerCase())) pending.add(entity);
          } else if (entity is File &&
              (name == '.env' || name.startsWith('.env.')) &&
              !RegExp(r'\.(example|template|sample)(\.|$)', caseSensitive: false).hasMatch(name)) {
            final resolved = await entity.resolveSymbolicLinks();
            if (resolved != entity.path || !resolved.startsWith('$root${Platform.pathSeparator}')) continue;
            final handle = await entity.open();
            Uint8List bytes;
            try {
              bytes = await handle.read(65537);
            } finally {
              await handle.close();
            }
            ProjectEnvironment? environment;
            try {
              if (bytes.length > 65536) throw const FormatException();
              environment = ProjectDotenv.parse(utf8.decode(bytes));
            } on FormatException {
              /* Report the filename without exposing its contents. */
            }
            result.add(
              ProjectEnvSource(
                root,
                resolved,
                resolved.substring(root.length + 1),
                bytes,
                environment,
                environment == null,
              ),
            );
          }
        }
      }
      result.sort((a, b) => a.name.compareTo(b.name));
      return result;
    } catch (_) {
      for (final source in result) {
        source.clear();
      }
      rethrow;
    }
  }
}
