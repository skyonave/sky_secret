import 'dart:async';

import 'package:flutter/services.dart';

import '../../../crypto/crypto.dart';

enum SecretDragResult { filled, partial, cancelled, unsupported, targetLost, targetChanged, missingValue, failed }

class SecretDragController {
  static const _channel = MethodChannel('skysecret/secret_drag');
  static int _sequence = 0;
  final Future<Object?> Function(String method, Object? arguments) _invoke;
  final void Function(bool active)? onActiveChanged;
  int? _active;
  bool _disposed = false;

  SecretDragController({
    Future<Object?> Function(String method, Object? arguments)? invoke,
    this.onActiveChanged,
  }) : _invoke = invoke ?? ((method, arguments) => _channel.invokeMethod<Object?>(method, arguments));

  bool get active => _active != null;

  Future<SecretDragResult> start({
    required VaultEntry entry,
    required Map<String, String> labels,
    required bool Function() allowed,
  }) async {
    if (_disposed || active || !allowed() || entry.isDeleted || entry.kind != VaultEntryKind.text) {
      return SecretDragResult.cancelled;
    }
    final id = ++_sequence;
    _active = id;
    onActiveChanged?.call(true);
    try {
      final epoch = await _invoke('prepare', null);
      if (_disposed || _active != id || !allowed() || epoch is! int || epoch < 0) {
        return SecretDragResult.cancelled;
      }
      final username = entry.copyProtectedUsername();
      try {
        final password = entry.copyProtectedPassword();
        try {
          final result = await _invoke('start', {
            'id': id,
            'epoch': epoch,
            'title': String.fromCharCodes(entry.title.runes.take(120)),
            'hover': labels['hover'],
            'login': labels['login'],
            'passwordLabel': labels['password'],
            'pairLabel': labels['pair'],
            'missingLogin': labels['missingLogin'],
            'missingPassword': labels['missingPassword'],
            'usernameSize': username.size,
            'username': username.data,
            'passwordSize': password.size,
            'password': password.data,
          });
          if (_disposed || _active != id || !allowed()) return SecretDragResult.cancelled;
          return switch (result) {
            'filled' => SecretDragResult.filled,
            'partial' => SecretDragResult.partial,
            'cancelled' => SecretDragResult.cancelled,
            'unsupported' => SecretDragResult.unsupported,
            'targetLost' => SecretDragResult.targetLost,
            'targetChanged' => SecretDragResult.targetChanged,
            'missingValue' => SecretDragResult.missingValue,
            _ => SecretDragResult.failed,
          };
        } finally {
          password.data.fillRange(0, password.data.length, 0);
        }
      } finally {
        username.data.fillRange(0, username.data.length, 0);
      }
    } finally {
      if (_active == id) {
        _active = null;
        onActiveChanged?.call(false);
      }
    }
  }

  void cancel() {
    final id = _active;
    if (id == null) return;
    _active = null;
    onActiveChanged?.call(false);
    unawaited(_invoke('cancel', id).catchError((_) => null));
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
