import 'dart:io';

import 'support/configuration_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/i18n/translations.g.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;

class OrganizationStore extends VaultStore {
  OrganizationStore(this.session) : super(file: File('unused-organization-test'));
  final VaultSession session;
  bool failNext = false;
  @override
  Future<bool> exists() async => true;
  @override
  Future<VaultSession> unlock(String password) async => session;
  @override
  Future<void> save(
    VaultSession session,
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('Synthetic failure');
    }
    session.acceptPersisted(
      session.persistedBytes,
      entries,
      folders ?? session.folders,
      name ?? session.name,
      revision: session.revision,
    );
  }
}

void main() {
  for (final locale in AppLocale.values) {
    ConfigurationHarness.testWidgets(
      'sections, drag/drop, rename/cancel, delete/undo: ${locale.name}',
      (tester) async {
        await LocaleSettings.setLocale(locale);
        final session = (await tester.runAsync(
          () => VaultCipher.create('Synthetic master 1!'),
        ))!;
        final store = OrganizationStore(session);
        final clipboard = FakeClipboard();
        final record = VaultEntry.create(
          title: 'Synthetic record',
          password: 'Synthetic secret',
        );
        await store.save(session, [record]);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(384, 504);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          SkySecretApp(
            desktop: FakeDesktop(),
            clipboard: clipboard,
            vaultStore: store,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('vault-master')),
          'Synthetic master 1!',
        );
        await tester.tap(find.byKey(const Key('open-vault')));
        await tester.pumpAndSettle();

        Future<void> commit(Future<void> Function() action) async {
          await action();
          await tester.pumpAndSettle();
        }

        await tester.tap(find.byKey(const Key('vault-heading')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.enterText(
          find.byKey(const Key('vault-name-input')),
          'Personal synthetic vault',
        );
        await commit(
          () => tester.tap(find.byKey(const Key('confirm-name'))),
        );
        expect(find.text('Personal synthetic vault'), findsOneWidget);
        await tester.tap(find.byKey(const Key('vault-heading')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('vault-name-input')),
          'Cancelled name',
        );
        await tester.tap(find.text(t.cancel));
        await tester.pumpAndSettle();
        expect(find.text('Personal synthetic vault'), findsOneWidget);

        await tester.tap(find.byKey(const Key('add-folder')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('vault-name-input')),
          'Synthetic section',
        );
        await commit(() => tester.tap(find.byKey(const Key('confirm-name'))));
        expect(find.text('Synthetic record'), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.text(t.vaultGeneral), findsNothing);
        expect(find.text(t.appName), findsOneWidget);
        final folderId = session.folders.single.id;
        final start = tester.getCenter(find.text('Synthetic record'));
        final end = tester.getCenter(
          find.byKey(ValueKey('folder-header-$folderId')),
        );
        await commit(() => tester.dragFrom(start, end - start));
        expect(session.entries.single.folderId, folderId);
        expect(clipboard.text, isNull);
        await tester.tap(find.byKey(ValueKey('folder-header-$folderId')));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic record'), findsNothing);
        await tester.tap(find.byKey(ValueKey('folder-header-$folderId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ValueKey('folder-header-$folderId')), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.vaultRenameFolder));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('vault-name-input')),
          'Renamed section',
        );
        await commit(() => tester.tap(find.byKey(const Key('confirm-name'))));
        expect(session.entries.single.folderId, folderId);
        expect(find.text('Renamed section'), findsOneWidget);

        await tester.tap(find.byKey(ValueKey('folder-header-$folderId')), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.vaultDeleteFolder));
        await tester.pumpAndSettle();
        await commit(() => tester.tap(find.widgetWithText(FilledButton, t.vaultDeleteFolder)));
        expect(session.folders, isEmpty);
        expect(session.entries.single.folderId, isNull);
        await tester.tap(find.text('Synthetic record'));
        await tester.pumpAndSettle();
        expect(clipboard.text, 'Synthetic secret');
        store.failNext = true;
        Future<void> delete() async {
          await tester.tap(find.text('Synthetic record'), buttons: kSecondaryMouseButton);
          await tester.pumpAndSettle();
          await tester.tap(find.text(t.vaultDeleteEntry));
        }

        await commit(delete);
        expect(find.text(t.vaultWriteFailed), findsOneWidget);
        expect(session.entries, hasLength(1));
        expect(clipboard.text, 'Synthetic secret');
        await commit(delete);
        expect(session.entries, isEmpty);
        expect(clipboard.text, isNull);
        await commit(() => tester.tap(find.byKey(ValueKey('undo-delete-${record.id}'))));
        expect(session.entries.single.password, 'Synthetic secret');
        expect(session.name, 'Personal synthetic vault');
        expect(session.folders, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
