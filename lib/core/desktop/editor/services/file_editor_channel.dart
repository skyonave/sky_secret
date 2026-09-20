import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

abstract final class FileEditorChannel {
  static Future<bool> connect({
    required WindowMethodChannel channel,
    required Future<int> Function() getWindowId,
    required Future<void> Function() onLock,
  }) async {
    await channel.setMethodCallHandler((call) async {
      if (call.method == 'lock') unawaited(onLock());
      return true;
    });
    final windowId = await getWindowId();
    return await channel.invokeMethod<bool>('privacy', windowId) == true;
  }
}
