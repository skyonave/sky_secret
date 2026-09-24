import 'package:flutter/services.dart';

abstract final class WindowsAutoStart {
  static const _channel = MethodChannel('skysecret/auto_start');

  static Future<bool> read() async {
    final enabled = await _channel.invokeMethod<bool>('read');
    if (enabled == null) throw StateError('Autostart status unavailable');
    return enabled;
  }

  static Future<void> setEnabled(bool enabled) async {
    final actual = await _channel.invokeMethod<bool>('set', enabled);
    if (actual != enabled) throw StateError('Autostart change was not confirmed');
  }
}
