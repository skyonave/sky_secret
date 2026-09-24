import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/sync/github/controllers/github_backup.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:skysecret/ui/vault/controllers/vault_session_controller.dart';

import 'github_test.dart' show MemoryStorage;
import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;

class DelayedSyncBackup extends GitHubBackup {
  final gate = Completer<void>();
  DelayedSyncBackup(VaultCatalog catalog) : super(catalog: catalog, storage: MemoryStorage(null));

  @override
  bool get signedIn => true;
  @override
  bool get usable => true;

  @override
  Future<void> synchronizeVault(String localId, VaultStore store, VaultSession session) async {
    busy = true;
    notifyListeners();
    await gate.future;
    busy = false;
    notifyListeners();
  }
}

void main() {
  testWidgets('one sync progress bar without layout shift', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    tester.view.physicalSize = const Size(460, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const notices = MethodChannel('skysecret/desktop_notice');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(notices, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(notices, null));
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('sync-progress-synthetic-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final catalog = VaultCatalog(directory: directory);
    const password = 'Synthetic sync progress password';
    await tester.runAsync(() async {
      final setup = VaultSessionController(catalog: catalog);
      await setup.load();
      await setup.open(password);
      setup.dispose();
    });
    final backup = DelayedSyncBackup(catalog);
    addTearDown(backup.dispose);
    await tester.pumpWidget(
      SkySecretApp(
        desktop: FakeDesktop(),
        clipboard: FakeClipboard(),
        vaultCatalog: catalog,
        githubBackup: backup,
      ),
    );
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (ready()) return;
      }
      fail('Synthetic UI did not become ready');
    }

    await until(() => find.byKey(const Key('vault-master')).evaluate().isNotEmpty);
    await tester.enterText(find.byKey(const Key('vault-master')), password);
    await tester.tap(find.byKey(const Key('open-vault')));
    await until(() {
      final add = find.byKey(const Key('add-entry')).evaluate().firstOrNull?.widget;
      return add is FilledButton && add.onPressed != null;
    });
    final footer = find.byKey(const Key('manager-footer'));
    final before = tester.getRect(footer);
    await tester.tap(find.byKey(const Key('synchronize-vault')));
    await tester.pump();
    expect(backup.busy, isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.descendant(of: footer, matching: find.byType(LinearProgressIndicator)), findsOneWidget);
    expect(tester.getRect(footer), before);
    expect(tester.widget<FilledButton>(find.byKey(const Key('add-entry'))).onPressed, isNull);
    backup.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.getRect(footer), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
