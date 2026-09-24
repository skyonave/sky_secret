import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/configuration/controllers/configuration_windows.dart';
import 'package:skysecret/core/desktop/desktop_actions.dart';
import 'package:skysecret/core/os/windows/window/hidden_window_frame.dart';
import 'package:skysecret/core/os/windows/window/window_work_area.dart';
import 'package:skysecret/core/settings/repositories/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import 'modal_window_lifecycle_probe.dart' show driver, waitFor;

class _TestDesktop extends DesktopActions {
  final bool inactive;
  _TestDesktop({this.inactive = false});
  @override
  String? get notice => null;

  @override
  Future<void> hide() async {
    onBeforeHide?.call();
    await windowManager.hide();
  }

  Future<void> show() async {
    await windowManager.show(inactive: inactive);
    if (!await windowManager.isVisible()) await windowManager.show(inactive: inactive);
    if (!inactive) await windowManager.focus();
    onAfterShow?.call();
  }

  @override
  Future<void> drag() => windowManager.startDragging();

  @override
  Future<String?> updateShortcut(HotKey shortcut) async => null;
}

Future<void> runVaultScenario(
  LiveWidgetController tester,
  Directory profile,
  void Function(String) log, {
  bool inactive = false,
}) async {
  log('VAULT_SETUP');
  final store = VaultStore(file: File('${profile.path}/vault.smv'));
  const password = 'Synthetic integration fixture passphrase';
  final fixture = await store.create(password, name: 'Integration fixture');
  await store.save(fixture, [
    VaultEntry.authenticator(title: 'Synthetic authenticator', totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
  ]);
  fixture.lock();
  final desktop = _TestDesktop(inactive: inactive);
  final preferences = VaultPreferences();
  await preferences.save(false, lockWhenHidden: false, captureAllowed: true);
  runApp(
    SkySecretApp(
      desktop: desktop,
      vaultStore: store,
      vaultCatalog: VaultCatalog(directory: profile),
      vaultPreferences: preferences,
    ),
  );
  await HiddenWindowFrame.prepare();
  if (inactive) {
    final area = WindowWorkArea.forWindow(await windowManager.getId());
    await windowManager.setBounds(Rect.fromLTWH(area.right - 472, area.bottom - 612, 460, 600));
  }
  await desktop.show();
  await waitFor(() => find.byKey(const Key('vault-master')).evaluate().isNotEmpty, 'Unlock form missing');
  final input = find.byKey(const Key('vault-master')).evaluate().single.widget as TextField;
  input.controller!.text = password;
  await tester.tap(find.byKey(const Key('open-vault')));
  await waitFor(() => find.byKey(const Key('add-entry')).evaluate().isNotEmpty, 'Fixture did not unlock');
  WindowMethodChannel? codes;
  await waitFor(() async {
    final windows = await WindowController.getAll();
    final child = windows.where((window) => window.arguments.contains('"totp"')).firstOrNull;
    if (child == null) return false;
    codes = driver(child.windowId);
    return (await codes!.invokeMethod<Map>('state'))?['visible'] == true;
  }, 'TOTP did not open after unlock');
  log('PASS TOTP after unlock');
  await ConfigurationWindows.prepare('en');
  final forms = (await WindowController.getAll()).singleWhere(
    (window) => window.arguments.contains('configuration-host'),
  );
  final form = driver(forms.windowId);
  for (final mode in ['cancel', 'cross', 'nativeClose']) {
    await tester.tap(find.byKey(const Key('add-entry')));
    await waitFor(() async => (await form.invokeMethod<Map>('state'))?['visible'] == true, 'Entry did not open');
    await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == false, 'TOTP remains over form');
    await form.invokeMethod(mode);
    await waitFor(() => !ConfigurationWindows.opened.value, 'Vault overlay remains');
    await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == true, 'TOTP did not restore');
    if (find.byKey(const Key('add-entry')).evaluate().isEmpty) throw StateError('Main UI replaced by editor');
    if (find.text(t.configurationInteractionBlocked).evaluate().isNotEmpty) {
      throw StateError('Vault overlay remains visible');
    }
    if (!inactive) await waitFor(windowManager.isFocused, 'Vault focus lost');
    log('PASS vault $mode and TOTP restore');
  }
  await codes!.invokeMethod('cross');
  await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == false, 'TOTP did not close');
  await desktop.hide();
  if (inactive) {
    final area = WindowWorkArea.forWindow(await windowManager.getId());
    await windowManager.setBounds(Rect.fromLTWH(area.right - 472, area.bottom - 612, 460, 600));
  }
  await desktop.show();
  await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == true, 'TOTP did not reopen');
  log('PASS TOTP cross and manager reopen');
  await desktop.hide();
  runApp(const SizedBox.shrink());
  await HiddenWindowFrame.prepare();
  desktop.dispose();
}
