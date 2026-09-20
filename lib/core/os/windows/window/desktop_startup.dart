import 'dart:async';

import 'package:flutter/services.dart';

import '../../../desktop/startup/controllers/startup_progress.dart';
import '../../../../i18n/translations.g.dart';

abstract final class DesktopStartup {
  static const _channel = MethodChannel('skysecret/startup');
  static StartupProgress? _progress;

  static Future<void> begin() async {
    _progress = StartupProgress(
      stages: {'desktop', 'forms', 'search', 'totp', 'vault', 'backup'},
      onComplete: (success) => unawaited(_send('finish', {'success': success})),
    );
    await _send('labels', {'loading': t.startupLoading, 'ready': t.startupReady, 'failed': t.startupFailed});
  }

  static Future<void> track(String stage, Future<void> Function() action) async {
    var success = false;
    try {
      await action();
      success = true;
    } finally {
      _progress?.finish(stage, success: success);
    }
  }

  static Future<void> _send(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (_) {}
  }
}
