import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';

class ConfigurationWindowPool {
  Future<PreparedConfigurationWindow>? _spare;
  int _generation = 0;

  Future<void> prepare(String locale) async {
    final pending = _spare ??= PreparedConfigurationWindow.create(locale);
    try {
      await pending;
    } catch (_) {
      if (identical(_spare, pending)) _spare = null;
      rethrow;
    }
  }

  Future<PreparedConfigurationWindow> acquire(String locale) async {
    final generation = _generation;
    final pending = _spare;
    _spare = null;
    final window = await (pending ?? PreparedConfigurationWindow.create(locale));
    window.generation = generation;
    return window;
  }

  Future<void> release(PreparedConfigurationWindow window) async {
    try {
      await window.reset();
      if (_spare == null && window.generation == _generation) {
        _spare = Future.value(window);
        return;
      }
    } catch (_) {}
    await window.dispose();
  }

  Future<void> dispose() async {
    _generation++;
    final pending = _spare;
    _spare = null;
    if (pending == null) return;
    try {
      await (await pending).dispose();
    } catch (_) {}
  }
}

class PreparedConfigurationWindow {
  final WindowMethodChannel channel;
  final ready = Completer<void>();
  WindowController? controller;
  int generation = 0;

  PreparedConfigurationWindow(this.channel);

  static Future<PreparedConfigurationWindow> create(String locale) async {
    final token = List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final window = PreparedConfigurationWindow(WindowMethodChannel('skysecret/configuration-host/$token'));
    try {
      await window.channel.setMethodCallHandler((call) async {
        if (call.method == 'ready' && !window.ready.isCompleted) window.ready.complete();
        return null;
      });
      window.controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({'type': 'configuration', 'channel': window.channel.name, 'locale': locale}),
        ),
      );
      await window.ready.future.timeout(const Duration(seconds: 20));
      return window;
    } catch (_) {
      await window.dispose();
      rethrow;
    }
  }

  Future<bool> activate(String sessionChannel, String locale) async =>
      await channel
          .invokeMethod<bool>('activate', {'channel': sessionChannel, 'locale': locale})
          .timeout(const Duration(seconds: 10)) ==
      true;

  Future<void> reset() async {
    final cleared = await channel.invokeMethod<bool>('reset').timeout(const Duration(seconds: 5));
    if (cleared != true) throw StateError('Configuration window did not reset');
  }

  Future<void> dispose() async {
    try {
      await controller?.hide();
    } catch (_) {}
    try {
      if (controller != null) await channel.invokeMethod('shutdown').timeout(const Duration(seconds: 2));
    } catch (_) {}
    await channel.setMethodCallHandler(null);
  }
}
