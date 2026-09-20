import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/os/windows/controllers/desktop_controller.dart';
import 'core/desktop/clipboard/services/sensitive_clipboard_boundary.dart';
import 'core/os/windows/services/windows_instance.dart';
import 'core/sync/github/controllers/github_backup.dart';
import 'i18n/translations.g.dart';
import 'ui/editor/file_editor_window.dart';
import 'ui/authenticator/totp_window.dart';
import 'ui/search/vault_search_window.dart';
import 'ui/shared/configuration/configuration_window.dart';
import 'core/desktop/configuration/controllers/configuration_windows.dart';
import 'core/os/windows/window/desktop_startup.dart';

Future<void> main(List<String> args) async {
  final clipboardBoundary = SensitiveClipboardBoundary();
  SensitiveWidgetsBinding(clipboardBoundary);
  await LocaleSettings.useDeviceLocale();
  if (!Platform.isWindows) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(t.windowsOnly))),
      ),
    );
    return;
  }
  if (await ConfigurationWindow.runIfNeeded(clipboardBoundary)) return;
  if (await FileEditorWindow.runIfNeeded(clipboardBoundary: clipboardBoundary)) return;
  if (await TotpWindow.runIfNeeded()) return;
  if (await VaultSearchWindow.runIfNeeded(clipboardBoundary: clipboardBoundary)) return;
  final WindowsInstance instance;
  try {
    instance = WindowsInstance();
  } catch (_) {
    exit(1);
  }
  if (!instance.isPrimary) {
    instance.dispose();
    exit(0);
  }
  final desktop = DesktopController(onExit: instance.dispose);
  instance.listen(() => unawaited(desktop.show()));
  final backup = GitHubBackup.local();
  await DesktopStartup.begin();
  runApp(SkySecretApp(desktop: desktop, githubBackup: backup, clipboardBoundary: clipboardBoundary));
  unawaited(
    DesktopStartup.track('backup', () async {
      await backup.initialize();
      if (backup.connectionNeedsRecovery) throw StateError('Backup settings unavailable');
    }).catchError((_) {}),
  );
  try {
    await DesktopStartup.track('desktop', desktop.initialize);
    unawaited(
      DesktopStartup.track(
        'forms',
        () => ConfigurationWindows.prepare(
          LocaleSettings.currentLocale.languageCode,
        ),
      ).catchError((_) {}),
    );
  } catch (_) {
    instance.dispose();
    exit(1);
  }
}
