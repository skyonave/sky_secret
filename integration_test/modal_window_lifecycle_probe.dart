import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/clipboard/services/sensitive_clipboard_boundary.dart';
import 'package:skysecret/core/desktop/configuration/controllers/configuration_windows.dart';
import 'package:skysecret/core/os/windows/window/hidden_window_frame.dart';
import 'package:skysecret/core/os/windows/window/window_privacy.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:skysecret/ui/authenticator/totp_window.dart';
import 'package:skysecret/ui/search/vault_search_window.dart';
import 'package:skysecret/ui/shared/app_theme.dart';
import 'package:skysecret/ui/shared/configuration/configuration_interaction_guard.dart';
import 'package:skysecret/ui/shared/configuration/configuration_window.dart';
import 'package:window_manager/window_manager.dart';

import 'modal_vault_scenario.dart';

Future<void> waitFor(
  FutureOr<bool> Function() condition,
  String label, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) throw StateError(label);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

WindowMethodChannel driver(String id) => WindowMethodChannel(
  'skysecret/integration/driver/$id',
  mode: ChannelMode.unidirectional,
);

Future<void> main() async {
  final profile = Platform.environment['LOCALAPPDATA'] ?? '';
  if (Platform.environment['SKYSECRET_MODAL_INTEGRATION'] != '1' ||
      !profile.contains('secret_manager\\application\\build\\')) {
    exit(2);
  }
  final boundary = SensitiveClipboardBoundary();
  SensitiveWidgetsBinding(boundary);
  final errors = File('$profile/framework-errors.log');
  void recordError(Object error) =>
      errors.writeAsStringSync('${error.runtimeType}\n', mode: FileMode.append, flush: true);
  FlutterError.onError = (details) => recordError(details.exception);
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    recordError(error);
    return true;
  };
  if (Platform.environment['SKYSECRET_STARTUP_INTEGRATION'] == '1') {
    runApp(const SizedBox.shrink());
    return;
  }
  await LocaleSettings.setLocale(AppLocale.en);
  final engine = await WindowController.fromCurrentEngine();
  final tester = LiveWidgetController(WidgetsBinding.instance);
  if (engine.arguments.isNotEmpty) {
    final args = jsonDecode(engine.arguments) as Map;
    if (args['type'] == 'configuration') {
      await ConfigurationWindow.runIfNeeded(boundary);
    } else if (args['type'] == 'totp') {
      await TotpWindow.runIfNeeded();
    } else if (args['type'] == 'search') {
      await VaultSearchWindow.runIfNeeded(clipboardBoundary: boundary);
    } else {
      throw StateError('Unexpected integration child');
    }
    await driver(engine.windowId).setMethodCallHandler((call) async {
      switch (call.method) {
        case 'state':
          final bounds = await windowManager.getBounds();
          return {
            'left': bounds.left,
            'right': bounds.right,
            'visible': await windowManager.isVisible(),
            'focused': await windowManager.isFocused(),
          };
        case 'cancel':
          await waitFor(() => find.text(t.cancel).evaluate().isNotEmpty, 'Cancel button missing');
          await tester.ensureVisible(find.text(t.cancel));
          await tester.tap(find.text(t.cancel));
          return true;
        case 'cross':
          await waitFor(() => find.byIcon(Icons.close_rounded).evaluate().isNotEmpty, 'Close button missing');
          await tester.tap(find.byIcon(Icons.close_rounded).first);
          return true;
        case 'nativeClose':
          await windowManager.close();
          return true;
        case 'save':
          await tester.ensureVisible(find.text(t.save));
          await tester.tap(find.text(t.save));
          return true;
      }
      return null;
    });
    return;
  }
  final report = File('$profile/modal-integration.log');
  void log(String value) => report.writeAsStringSync('$value\n', mode: FileMode.append, flush: true);
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(const WindowOptions(size: Size(460, 600), skipTaskbar: true));
  await windowManager.setTitle('SkySecret integration fixture');
  await windowManager.setPreventClose(true);
  await WindowPrivacy.initialize(captureAllowed: true);
  if (Platform.environment['SKYSECRET_SECTION_INTEGRATION'] == '1') {
    try {
      await runVaultScenario(tester, Directory(profile), log, inactive: true);
      if (errors.existsSync()) throw StateError('Framework errors were recorded');
      log('SUCCESS');
    } catch (error) {
      log('FAIL ${error.runtimeType}: $error');
    } finally {
      await ConfigurationWindows.dispose();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
    return;
  }
  var clicks = 0;
  Future<dynamic>? pending;
  runApp(
    TranslationProvider(
      child: MaterialApp(
        theme: AppTheme.theme,
        home: ConfigurationInteractionGuard(
          child: Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () {
                    pending = ConfigurationWindows.open(
                      kind: 'entry',
                      locale: 'en',
                      data: {
                        'fields': {
                          for (final field in ['title', 'username', 'password', 'notes', 'totp', 'host', 'port'])
                            field: '',
                        },
                        'folders': <dynamic>[],
                      },
                      isValid: () => true,
                      onAction: (method, value) async => null,
                    );
                  },
                  child: const Text('Open form'),
                ),
                TextButton(onPressed: () => clicks++, child: const Text('Underlying action')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await HiddenWindowFrame.prepare();
  try {
    await ConfigurationWindows.prepare('en');
    final windows = await WindowController.getAll();
    final child = windows.singleWhere((window) => window.arguments.contains('configuration-host'));
    final remote = driver(child.windowId);
    if ((await remote.invokeMethod<Map>('state'))?['visible'] == true) {
      throw StateError('Preloaded form is visible');
    }
    await windowManager.show();
    await windowManager.focus();
    log('WAITING_FOR_ACTIVATION');
    await waitFor(windowManager.isFocused, 'Test window was not activated', timeout: const Duration(seconds: 60));
    for (final mode in ['cancel', 'cross', 'nativeClose', 'save', 'cancel', 'cross', 'nativeClose', 'save']) {
      log('OPEN $mode');
      await tester.tap(find.text('Open form'));
      await waitFor(() async {
        try {
          final state = await remote.invokeMethod<Map>('state');
          return state?['visible'] == true && state?['focused'] == true;
        } catch (_) {
          return false;
        }
      }, 'Form did not become visible');
      await waitFor(() => find.text(t.configurationInteractionBlocked).evaluate().isNotEmpty, 'Overlay missing');
      if (!ConfigurationWindows.opened.value) throw StateError('Modal state missing');
      log('VISIBLE $mode');
      await remote.invokeMethod(mode);
      await waitFor(() => !ConfigurationWindows.opened.value, 'Overlay remains after $mode');
      final result = await pending!.timeout(const Duration(seconds: 2));
      if (mode == 'save' && result != true) throw StateError('Saved result was lost');
      await waitFor(() => find.text(t.configurationInteractionBlocked).evaluate().isEmpty, 'Overlay widget remains');
      await waitFor(
        () async => await windowManager.isVisible() && await windowManager.isFocused(),
        'Parent focus lost',
      );
      final before = clicks;
      await tester.tap(find.text('Underlying action'));
      if (clicks != before + 1) throw StateError('Parent input still blocked');
      final remaining = await WindowController.getAll();
      if (remaining.where((window) => window.arguments.contains('configuration-host')).length != 1) {
        throw StateError('Form engine was not reused');
      }
      log('PASS $mode');
    }
    await runVaultScenario(tester, Directory(profile), log);
    if (errors.existsSync()) throw StateError('Framework errors were recorded');
    log('SUCCESS');
  } catch (error) {
    log('FAIL ${error.runtimeType}: $error');
  } finally {
    ConfigurationWindows.closeAll();
    try {
      await ConfigurationWindows.dispose().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
