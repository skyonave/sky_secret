import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../crypto/crypto.dart';
import '../models/project_launch_profile.dart';

class ProjectLaunchController extends ChangeNotifier {
  final MethodChannel channel;
  final _running = <String, String>{};
  final _starting = <String, String>{};
  final _exitCodes = <String, int>{};
  Timer? _timer;
  int _epoch = 0;
  int _sequence = 0;
  bool _disposed = false;
  bool _polling = false;

  ProjectLaunchController({this.channel = const MethodChannel('skysecret/project-launch')});

  bool running(String id) => _running.containsKey(id);
  bool starting(String id) => _starting.containsKey(id);
  int? exitCode(String id) => _exitCodes[id];

  Future<bool> start({
    required String id,
    required VaultSession session,
    required VaultEntry entry,
    required ProjectLaunchProfile profile,
  }) async {
    if (_disposed || session.isLocked || running(id) || starting(id) || entry.isDeleted) return false;
    if (!entry.isEnvironment || entry.conflictOf != null || !session.entries.contains(entry)) return false;
    final epoch = _epoch;
    final environment = ProjectEnvironment.decode(entry.notes);
    profile.checkSecrets(environment.variables.values);
    final request = '${++_sequence}:$id';
    _starting[id] = request;
    _exitCodes.remove(id);
    notifyListeners();
    try {
      final grant = await channel.invokeMethod<int>('prepare');
      if (grant == null || _disposed || epoch != _epoch || session.isLocked || _starting[id] != request) return false;
      final result = await channel.invokeMethod<bool>('start', {
        'epoch': grant,
        'id': request,
        ...profile.toJson(),
        'environment': environment.variables,
      });
      if (_disposed || epoch != _epoch || session.isLocked || _starting[id] != request) {
        await channel.invokeMethod('stop', request);
        return false;
      }
      if (result != true) return false;
      _running[id] = request;
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
      return true;
    } finally {
      if (_starting[id] == request) _starting.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop(String id) async {
    final request = _running.remove(id) ?? _starting.remove(id);
    if (request != null) await channel.invokeMethod('stop', request);
    if (!_disposed) notifyListeners();
  }

  Future<void> stopProject(String lineage) async {
    final ids = {..._running.keys, ..._starting.keys}.where((id) => id.startsWith('$lineage/')).toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  Future<void> _poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    final epoch = _epoch;
    try {
      final statuses = await channel.invokeMapMethod<String, dynamic>('status');
      if (_disposed || epoch != _epoch || statuses == null) return;
      for (final item in Map<String, String>.of(_running).entries) {
        final code = statuses[item.value];
        if (code is int) {
          _running.remove(item.key);
          _exitCodes[item.key] = code;
        }
      }
      notifyListeners();
    } catch (_) {
      revoke();
    } finally {
      _polling = false;
      if (_running.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void revoke() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _running.clear();
    _starting.clear();
    _exitCodes.clear();
    unawaited(channel.invokeMethod('revoke').catchError((_) => null));
    if (!_disposed) notifyListeners();
  }

  void lock() {
    _epoch++;
    _starting.clear();
    unawaited(channel.invokeMethod('lock').catchError((_) => null));
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    revoke();
    super.dispose();
  }
}
