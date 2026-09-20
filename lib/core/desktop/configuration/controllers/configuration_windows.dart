import 'dart:async';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../../os/windows/window/window_privacy.dart';
import 'configuration_window_pool.dart';

abstract final class ConfigurationWindows {
  static const _placement = MethodChannel('skysecret/companion');
  static final _windows = <_Configuration>[];
  static final opened = ValueNotifier(false);
  static final _pool = ConfigurationWindowPool();
  static bool Function(int) registerWindow = WindowPrivacy.registerWindow;
  static bool isChild = false;
  static void Function()? onActivity;
  static void Function()? onBlur;
  static Future<bool> Function(String)? copy;
  static Future<void> Function()? clearClipboard;

  static bool get isOpen => _windows.isNotEmpty;

  static Future<void> prepare(String locale) => _pool.prepare(locale);

  static Future<void> dispose() async {
    closeAll();
    await _pool.dispose();
  }

  static Future<dynamic> open({
    required String kind,
    required String locale,
    Map<String, dynamic> data = const {},
    required bool Function() isValid,
    Future<dynamic> Function(String, dynamic)? onAction,
  }) async {
    if (!isValid()) return null;
    final token = List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final window = _Configuration(WindowMethodChannel('skysecret/configuration/$token'), isValid);
    _windows.add(window);
    opened.value = true;
    try {
      await window.channel.setMethodCallHandler((call) async {
        if (!window.active || !isValid()) {
          if (!window.result.isCompleted) window.result.complete();
          return null;
        }
        if (call.method == 'complete') {
          if (!window.result.isCompleted) window.result.complete(window.connected ? call.arguments : null);
          return true;
        }
        if (call.method == 'connect') {
          final id = call.arguments;
          if (id is int && registerWindow(id)) {
            final placed = await _placement.invokeMethod<bool>('placeConfiguration', {'window': id, 'gap': 12.0});
            window.connected = placed == true && window.active && isValid();
            window.windowId = id;
          }
          return window.connected;
        }
        if (!window.connected) return null;
        switch (call.method) {
          case 'closing':
            final index = _windows.indexOf(window);
            final previous = index > 0 ? _windows[index - 1] : null;
            if (previous != null && (!previous.active || !previous.isValid())) return false;
            return _placement.invokeMethod<bool>('returnFocus', {
              'window': window.windowId,
              if (previous != null) 'target': previous.windowId,
            });
          case 'read':
            if (window.read) return null;
            window.read = true;
            return {'kind': kind, 'data': data};
          case 'alive':
            return true;
          case 'activity':
            onActivity?.call();
            return true;
          case 'blur':
            onBlur?.call();
            return true;
          case 'copy':
            if (call.arguments is String) {
              final copied = await copy?.call(call.arguments as String) ?? false;
              if (!window.active || !isValid()) {
                await clearClipboard?.call();
                return false;
              }
              return copied;
            }
            return false;
          default:
            if (call.method != 'state') onActivity?.call();
            final response = await onAction?.call(call.method, call.arguments);
            return window.active && isValid() ? response : null;
        }
      });
      if (!window.active || !isValid()) return null;
      window.timeout = Timer(const Duration(seconds: 20), () {
        if (!window.read && !window.result.isCompleted) window.result.complete();
      });
      window.prepared = await _pool.acquire(locale);
      window.controller = window.prepared!.controller;
      if (!window.active || !isValid()) return null;
      final activated = await window.prepared!.activate(window.channel.name, locale);
      if (activated == false || !window.active || !isValid()) return null;
      return await window.result.future;
    } finally {
      window.active = false;
      window.timeout?.cancel();
      _windows.remove(window);
      try {
        await _close(window);
      } finally {
        opened.value = _windows.isNotEmpty;
      }
      final previous = _windows.lastOrNull;
      if (previous != null && previous.active && previous.isValid() && previous.connected) {
        await _placement.invokeMethod<bool>('placeConfiguration', {'window': previous.windowId, 'gap': 12.0});
        if (previous.active && previous.isValid()) await previous.controller?.show();
      }
    }
  }

  static void closeAll() {
    for (final window in List<_Configuration>.of(_windows)) {
      window.active = false;
      if (!window.result.isCompleted) window.result.complete();
      unawaited(window.controller?.hide().catchError((_) {}) ?? Future<void>.value());
    }
    _windows.clear();
    opened.value = false;
  }

  static Future<void> _close(_Configuration window) async {
    final prepared = window.prepared;
    try {
      if (prepared != null) await _pool.release(prepared);
    } finally {
      await window.channel.setMethodCallHandler(null);
    }
  }
}

class _Configuration {
  final WindowMethodChannel channel;
  final bool Function() isValid;
  final result = Completer<dynamic>();
  WindowController? controller;
  PreparedConfigurationWindow? prepared;
  bool active = true;
  bool connected = false;
  bool read = false;
  Timer? timeout;
  int? windowId;

  _Configuration(this.channel, this.isValid);
}
