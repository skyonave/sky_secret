import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/configuration/controllers/configuration_windows.dart';
import 'package:skysecret/core/desktop/desktop_actions.dart';
import 'package:skysecret/core/desktop/focus_dismissal.dart';
import 'package:skysecret/core/os/windows/window/hidden_window_frame.dart';
import 'package:skysecret/core/os/windows/window/window_work_area.dart';
import 'package:skysecret/core/settings/repositories/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:window_manager/window_manager.dart';

import 'package:skysecret/ui/vault/controllers/vault_session_controller.dart';

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
  bool sectionsOnly = false,
}) async {
  log('VAULT_SETUP');
  final store = VaultStore(file: File('${profile.path}/vault.smv'));
  const password = 'Synthetic integration fixture passphrase';
  final fixture = await store.create(password, name: 'Integration fixture');
  await store.save(fixture, [
    VaultEntry.authenticator(title: 'Synthetic authenticator', totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
  ]);
  fixture.lock();
  if (sectionsOnly) {
    final setup = VaultSessionController(
      store: store,
      catalog: VaultCatalog(directory: profile),
    );
    await setup.load();
    await setup.open(password);
    final project = (await setup.createProject('Synthetic project'))!;
    await setup.selectProject(project);
    await setup.save([
      VaultEntry(
        id: 'synthetic-env',
        title: 'Development',
        username: '',
        password: '',
        notes: ProjectEnvironment({'TOKEN': 'synthetic', 'EMPTY': ''}).encode(),
        kind: VaultEntryKind.environment,
      ),
      VaultEntry.create(title: 'Synthetic account', password: 'synthetic password'),
    ]);
    setup.dispose();
  }
  final desktop = _TestDesktop(inactive: sectionsOnly);
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
  if (sectionsOnly) {
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
  for (var cycle = 0; cycle < 3; cycle++) {
    await tester.tap(find.text(t.projects));
    await waitFor(
      () async => (await codes!.invokeMethod<Map>('state'))?['visible'] == false,
      'TOTP remains in Projects',
    );
    await tester.tap(find.text(t.general));
    await waitFor(
      () async => (await codes!.invokeMethod<Map>('state'))?['visible'] == true,
      'TOTP missing after Projects',
    );
    log('PASS Projects to General $cycle');
  }
  if (sectionsOnly) {
    await tester.tap(find.text(t.projects));
    await waitFor(() => find.text('Synthetic project').evaluate().isNotEmpty, 'Project missing from list');
    await tester.tap(find.text('Synthetic project'));
    await waitFor(() => find.byKey(const Key('environment-switcher')).evaluate().isNotEmpty, 'Project did not open');
    WindowMethodChannel? secrets;
    await waitFor(() async {
      for (final window in await WindowController.getAll()) {
        if (!window.arguments.contains('configuration-host')) continue;
        final channel = driver(window.windowId);
        Map? state;
        try {
          state = await channel.invokeMethod<Map>('state');
        } on WindowChannelException {
          continue;
        }
        if (state?['secrets'] == true && state?['visible'] == true) {
          secrets = channel;
          return true;
        }
      }
      return false;
    }, 'Project secrets did not open');
    if (ConfigurationWindows.opened.value) throw StateError('Secrets blocked main window');
    log('PASS project secrets nonmodal');
    await secrets!.invokeMethod('reveal');
    await waitFor(
      () async => (await secrets!.invokeMethod<Map>('state'))?['revealed'] == true,
      'ENV eye did not reveal requested value',
    );
    log('PASS ENV eye reveals through owner channel');
    await tester.tap(find.text(t.projectEnvironmentAdd));
    WindowMethodChannel? editor;
    await waitFor(() async {
      for (final window in await WindowController.getAll()) {
        if (!window.arguments.contains('configuration-host')) continue;
        final channel = driver(window.windowId);
        Map? state;
        try {
          state = await channel.invokeMethod<Map>('state');
        } on WindowChannelException {
          continue;
        }
        if (state?['environment'] == true && state?['visible'] == true) {
          editor = channel;
          return true;
        }
      }
      return false;
    }, 'Third window did not open');
    final middle = (await secrets!.invokeMethod<Map>('state'))!;
    final left = (await editor!.invokeMethod<Map>('state'))!;
    if (middle['visible'] != true || (left['right'] as num) > (middle['left'] as num)) {
      throw StateError('Project windows overlap or secrets disappeared');
    }
    log('PASS three window placement');
    await waitFor(
      () async => (await secrets!.invokeMethod<Map>('state'))?['revealed'] == false,
      'ENV remains revealed while editing',
    );
    await editor!.invokeMethod('cancel');
    await waitFor(() => !ConfigurationWindows.opened.value, 'Project editor remains blocking');
    if ((await secrets!.invokeMethod<Map>('state'))?['visible'] != true) throw StateError('Secrets lost after editor');
    log('PASS secrets survive editor close');
    var ownWindowFocused = true;
    final dismissal = FocusDismissal(
      readState: () async => (protectedFocus: ownWindowFocused, leftDown: false, cancelDrag: false, fileOver: false),
      dismiss: desktop.hide,
    );
    dismissal.request();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if ((await secrets!.invokeMethod<Map>('state'))?['visible'] != true) {
      throw StateError('Internal focus transition hid secrets');
    }
    ownWindowFocused = false;
    await waitFor(
      () async => (await secrets!.invokeMethod<Map>('state'))?['visible'] == false,
      'Secrets remain after group focus loss',
    );
    dismissal.cancel();
    if (await windowManager.isVisible()) throw StateError('Manager remains after group focus loss');
    log('PASS group focus loss hides windows; internal transitions preserve them (synthetic focus state)');
    await desktop.show();
    await waitFor(() => find.byKey(const Key('lock-vault')).evaluate().isNotEmpty, 'Header lock missing');
    await tester.tap(find.byKey(const Key('lock-vault')));
    await waitFor(
      () => find.byKey(const Key('vault-master')).evaluate().isNotEmpty,
      'Header lock did not lock workspace',
    );
    if (find.byKey(const Key('environment-switcher')).evaluate().isNotEmpty) {
      throw StateError('Project stayed unlocked');
    }
    log('PASS header locks workspace and project');
    final master = find.byKey(const Key('vault-master')).evaluate().single.widget as TextField;
    master.controller!.text = password;
    await tester.tap(find.byKey(const Key('open-vault')));
    await waitFor(() {
      final add = find.byKey(const Key('add-entry')).evaluate().firstOrNull?.widget;
      final projects = find.widgetWithText(TextButton, t.projects).evaluate().firstOrNull?.widget;
      return add is FilledButton && add.onPressed != null && projects is TextButton && projects.onPressed != null;
    }, 'Workspace did not finish reopening');
    await tester.tap(find.text(t.projects));
    await waitFor(() => find.text('Synthetic project').evaluate().isNotEmpty, 'Project lost after lock');
    for (final confirm in [false, true]) {
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      WindowMethodChannel? confirmation;
      await waitFor(() async {
        for (final window in await WindowController.getAll()) {
          if (!window.arguments.contains('configuration-host')) continue;
          final channel = driver(window.windowId);
          try {
            final state = await channel.invokeMethod<Map>('state');
            if (state?['visible'] == true && state?['deleteConfirm'] == true) {
              confirmation = channel;
              return true;
            }
          } on WindowChannelException {
            continue;
          }
        }
        return false;
      }, 'Project deletion confirmation missing');
      await confirmation!.invokeMethod(confirm ? 'confirmDelete' : 'cancel');
      await waitFor(() => !ConfigurationWindows.opened.value, 'Deletion confirmation stayed open');
      if (!confirm) {
        if (find.text('Synthetic project').evaluate().isEmpty) throw StateError('Cancel deleted project');
        if (!(await VaultCatalog(directory: profile).list()).any((v) => v.isProject)) {
          throw StateError('Cancel removed project file');
        }
      } else {
        await waitFor(() => find.text('Synthetic project').evaluate().isEmpty, 'Confirmed project remains listed');
        if ((await VaultCatalog(directory: profile).list()).any((v) => v.isProject)) {
          throw StateError('Confirmed project file still exists');
        }
      }
    }
    log('PASS project deletion Cancel preserves data; confirmation removes file and list entry');
    await desktop.hide();
    runApp(const SizedBox.shrink());
    await HiddenWindowFrame.prepare();
    desktop.dispose();
    return;
  }
  final forms = (await WindowController.getAll()).singleWhere(
    (window) => window.arguments.contains('configuration-host'),
  );
  final form = driver(forms.windowId);
  for (final mode in ['cancel', 'cross', 'nativeClose']) {
    await tester.tap(find.byKey(const Key('add-entry')));
    await waitFor(() async => (await form.invokeMethod<Map>('state'))?['focused'] == true, 'Entry did not focus');
    await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == false, 'TOTP remains over form');
    await form.invokeMethod(mode);
    await waitFor(() => !ConfigurationWindows.opened.value, 'Vault overlay remains');
    await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == true, 'TOTP did not restore');
    if (find.byKey(const Key('add-entry')).evaluate().isEmpty) throw StateError('Main UI replaced by editor');
    if (find.text(t.configurationInteractionBlocked).evaluate().isNotEmpty) {
      throw StateError('Vault overlay remains visible');
    }
    await waitFor(windowManager.isFocused, 'Vault focus lost');
    log('PASS vault $mode and TOTP restore');
  }
  await codes!.invokeMethod('cross');
  await waitFor(() async => (await codes!.invokeMethod<Map>('state'))?['visible'] == false, 'TOTP did not close');
  await desktop.hide();
  if (sectionsOnly) {
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
