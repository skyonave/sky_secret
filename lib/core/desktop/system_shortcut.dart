import 'package:hotkey_manager/hotkey_manager.dart';

abstract final class SystemShortcut {
  static Future<void> register(HotKey key, {required HotKeyHandler keyDownHandler}) {
    final nativeKey = HotKey(
      identifier: key.identifier,
      key: key.physicalKey,
      modifiers: key.modifiers ?? [],
      scope: key.scope,
    );
    return hotKeyManager.register(nativeKey, keyDownHandler: keyDownHandler);
  }
}
