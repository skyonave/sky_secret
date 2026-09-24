import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart' as testing;
import 'package:skysecret/core/desktop/configuration/controllers/configuration_windows.dart';
import 'package:skysecret/core/os/windows/window/window_privacy.dart';
import 'package:skysecret/ui/shared/input/sensitive_text_editing.dart';
import 'package:skysecret/ui/vault/vault_panel.dart';

class ConfigurationHarness {
  static const _windows = MethodChannel('mixin.one/desktop_multi_window');
  static const _channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  static const _placement = MethodChannel('skysecret/companion');
  static const _notice = MethodChannel('skysecret/desktop_notice');
  static const _autoStart = MethodChannel('skysecret/auto_start');
  final WidgetTester tester;
  final _routes = <String, Route<dynamic>>{};
  final _sessions = <String, String>{};
  int _sequence = 0;

  ConfigurationHarness(this.tester);

  static Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(finder, findsWidgets);
  }

  static void testWidgets(String description, Future<void> Function(WidgetTester) body) {
    testing.testWidgets(description, (tester) async {
      final harness = ConfigurationHarness(tester)..attach();
      try {
        await body(tester);
      } finally {
        ConfigurationWindows.closeAll();
        await tester.pumpWidget(const SizedBox.shrink());
        var disposed = false;
        final disposal = harness.dispose().then((_) => disposed = true);
        for (var attempt = 0; attempt < 30 && !disposed; attempt++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(disposed, isTrue, reason: 'Configuration harness must release its window channels');
        await disposal;
      }
    });
  }

  void attach() {
    final messenger = tester.binding.defaultBinaryMessenger;
    ConfigurationWindows.registerWindow = (_) => true;
    messenger.setMockMethodCallHandler(_placement, (_) async => true);
    messenger.setMockMethodCallHandler(_notice, (_) async => null);
    messenger.setMockMethodCallHandler(_autoStart, (_) async => false);
    messenger.setMockMethodCallHandler(_windows, (call) async {
      if (call.method == 'createWindow') {
        final data = jsonDecode((call.arguments as Map)['arguments'] as String) as Map;
        await _send(data['channel'] as String, 'ready');
        return 'synthetic-window-${++_sequence}';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_channels, (call) async {
      if (call.method != 'invokeMethod') return null;
      final data = call.arguments as Map;
      final host = data['channel'] as String;
      final method = data['method'];
      if (method == 'activate') {
        final session = (data['arguments'] as Map)['channel'] as String;
        if (await _send(session, 'connect', 42) != true) return false;
        final payload = await _send(session, 'read') as Map?;
        if (payload == null) return false;
        final kind = payload['kind'] as String;
        final navigator = (find.byType(Navigator).evaluate().first as StatefulElement).state as NavigatorState;
        final route = MaterialPageRoute<dynamic>(
          builder: (context) => CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, _) {
                unawaited(_send(session, 'activity'));
                return KeyEventResult.ignored;
              },
              child: Listener(
                onPointerDown: (_) => unawaited(_send(session, 'activity')),
                child: SensitiveClipboardScope(
                  copy: (text) async => await _send(session, 'copy', text) == true,
                  child: VaultConfigurationForms(
                    kind: kind,
                    data: Map<String, dynamic>.from(payload['data'] as Map),
                    action: (method, value) => _send(session, method, value),
                  ),
                ),
              ),
            ),
          ),
        );
        _routes[host] = route;
        _sessions[host] = session;
        unawaited(
          navigator.push(route).then((value) async {
            if (_sessions[host] == session) {
              await _send(session, 'complete', VaultConfigurationForms.encode(kind, value));
            }
          }),
        );
        return true;
      }
      if (method == 'reset' || method == 'shutdown') {
        _sessions.remove(host);
        final route = _routes.remove(host);
        if (route != null && route.isActive) route.navigator?.removeRoute(route);
        return true;
      }
      return null;
    });
  }

  Future<dynamic> _send(String channel, String method, [dynamic value]) async {
    final reply = Completer<ByteData?>();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channels.name,
      _channels.codec.encodeMethodCall(
        MethodCall('methodCall', {'channel': channel, 'method': method, 'arguments': value}),
      ),
      reply.complete,
    );
    try {
      return _channels.codec.decodeEnvelope((await reply.future)!);
    } on PlatformException {
      if (_sessions.containsValue(channel)) rethrow;
      return null;
    }
  }

  Future<void> dispose() async {
    ConfigurationWindows.closeAll();
    await ConfigurationWindows.dispose();
    ConfigurationWindows.registerWindow = WindowPrivacy.registerWindow;
    for (final channel in [_windows, _channels, _placement, _notice, _autoStart]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  }
}
