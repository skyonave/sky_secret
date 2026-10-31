import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/app.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/search/controllers/vault_search_presenter.dart';
import 'package:skysecret/core/settings/repositories/vault_preferences.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:skysecret/ui/vault/vault_panel.dart';
import 'package:skysecret/ui/shared/app_theme.dart';

import 'manager_window_test.dart' show FakeDesktop, FakeClipboard;
import 'vault_organization_ui_test.dart' show OrganizationStore;
import 'support/configuration_harness.dart';

class DeferredCatalogStore extends OrganizationStore {
  final ready = Completer<bool>();
  DeferredCatalogStore(super.session);
  @override
  Future<bool> exists() => ready.future;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('skysecret/desktop_notice'),
      (_) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('skysecret/desktop_notice'),
      null,
    );
  });
  Future<void> mount(WidgetTester tester, OrganizationStore store, FakeDesktop desktop, FakeClipboard clipboard) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(460, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = VaultPreferences();
    await preferences.save(false, lockWhenHidden: false);
    await tester.pumpWidget(
      SkySecretApp(desktop: desktop, clipboard: clipboard, vaultStore: store, vaultPreferences: preferences),
    );
    await tester.pump();
  }

  for (final shownBeforeLoad in [false, true]) {
    ConfigurationHarness.testWidgets(
      'showing a locked vault focuses password, including delayed load: $shownBeforeLoad',
      (tester) async {
        final session = (await tester.runAsync(() => VaultCipher.create('Synthetic master 1!')))!;
        final store = DeferredCatalogStore(session);
        final desktop = FakeDesktop();
        if (!shownBeforeLoad) store.ready.complete(true);
        await mount(tester, store, desktop, FakeClipboard());
        desktop.onAfterShow!();
        await tester.pump();
        if (shownBeforeLoad) store.ready.complete(true);
        await tester.pumpAndSettle();
        final master = find.byKey(const Key('vault-master'));
        expect(tester.widget<TextField>(master).focusNode!.hasFocus, isTrue);
        tester.testTextInput.enterText('Synthetic typed immediately');
        await tester.pump();
        expect(tester.widget<TextField>(master).controller!.text, 'Synthetic typed immediately');
        desktop.onBeforeHide!();
        await tester.pumpAndSettle();
        tester.widget<TextField>(master).focusNode!.unfocus();
        await tester.pump();
        desktop.onAfterShow!();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(master).focusNode!.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        session.lock();
      },
    );
  }

  ConfigurationHarness.testWidgets('a delayed load cannot request password focus after hiding', (tester) async {
    final session = (await tester.runAsync(() => VaultCipher.create('Synthetic master 1!')))!;
    final store = DeferredCatalogStore(session);
    final desktop = FakeDesktop();
    await mount(tester, store, desktop, FakeClipboard());
    desktop.onAfterShow!();
    desktop.onBeforeHide!();
    store.ready.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('vault-master'))).focusNode!.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    session.lock();
  });

  for (final locale in AppLocale.values) {
    testWidgets('search filters the existing tree, favorites and all matches: ${locale.name}', (tester) async {
      await LocaleSettings.setLocale(locale);
      const native = MethodChannel('mixin.one/desktop_multi_window');
      const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
      const placement = MethodChannel('skysecret/companion');
      final messenger = tester.binding.defaultBinaryMessenger;
      var channel = '';
      var epoch = 0;
      Future<dynamic> invoke(String method, [Object? args]) async {
        final reply = Completer<ByteData?>();
        await messenger.handlePlatformMessage(
          channels.name,
          channels.codec.encodeMethodCall(
            MethodCall('methodCall', {'channel': channel, 'method': method, 'arguments': args}),
          ),
          reply.complete,
        );
        return channels.codec.decodeEnvelope((await reply.future)!);
      }

      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'createWindow') {
          final args = jsonDecode((call.arguments as Map)['arguments'] as String) as Map;
          if (args['type'] != 'search') throw MissingPluginException();
          channel = args['channel'] as String;
          await invoke('privacy', 123);
          await invoke('ready');
          return 'synthetic-search';
        }
        return null;
      });
      messenger.setMockMethodCallHandler(channels, (call) async {
        if (call.method == 'invokeMethod') {
          final args = call.arguments as Map;
          if (args['method'] == 'activate') epoch = (args['arguments'] as Map)['epoch'] as int;
        }
        return true;
      });
      messenger.setMockMethodCallHandler(placement, (_) async => true);
      addTearDown(() {
        for (final channel in [native, channels, placement]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      final session = (await tester.runAsync(() => VaultCipher.create('Synthetic master 1!')))!;
      final section = VaultFolder.create('Section');
      final folder = VaultFolder.create('Nested', parentId: section.id);
      final unrelated = VaultFolder.create('Unrelated');
      final nested = VaultEntry.create(title: 'Match nested', folderId: folder.id);
      final favorite = VaultEntry.create(title: 'Match favorite').withFavorite(true);
      final other = VaultEntry.create(title: 'Other record', folderId: unrelated.id);
      final matches = List.generate(60, (index) => VaultEntry.create(title: 'Match $index').atPosition(null, index));
      final store = OrganizationStore(session);
      await store.save(session, [nested, favorite, other, ...matches], folders: [section, folder, unrelated]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(460, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(
              body: VaultPanel(
                store: store,
                preferences: VaultPreferences(),
                searchPresenter: VaultSearchPresenter(registerWindow: (_) => true),
                copySecret: (_) async => true,
                clearClipboard: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('vault-master')), 'Synthetic master 1!');
      await tester.tap(find.byKey(const Key('open-vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('folder-header-${section.id}')));
      await tester.tap(find.text(t.browserFavorites));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('entry-card-${nested.id}')), findsNothing);
      expect(find.byKey(ValueKey('entry-card-${favorite.id}')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF, physicalKey: PhysicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(epoch, greaterThan(0));
      expect(await invoke('search', {'epoch': epoch, 'query': 'match'}), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('entry-card-${nested.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('entry-card-${favorite.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('entry-card-${other.id}')), findsNothing);
      expect(find.text('Unrelated'), findsNothing);
      for (final entry in matches) {
        expect(find.byKey(ValueKey('entry-card-${entry.id}')), findsOneWidget);
      }
      expect(find.byKey(const Key('vault-search-query')), findsNothing);
      expect(await invoke('search', {'epoch': epoch, 'query': 'no match anywhere'}), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(t.browserNoResults), findsOneWidget);
      expect(find.text('Section'), findsNothing);
      expect(await invoke('search', {'epoch': epoch, 'query': ''}), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(t.browserNoResults), findsNothing);
      expect(find.text('Unrelated'), findsOneWidget);
      expect(find.byKey(ValueKey('entry-card-${nested.id}')), findsNothing);
      expect(find.byKey(ValueKey('entry-card-${favorite.id}')), findsNothing);
      expect(await invoke('search', {'epoch': epoch, 'query': 'match'}), isTrue);
      await tester.pumpAndSettle();
      expect(await invoke('closed', {'epoch': epoch}), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('entry-card-${nested.id}')), findsNothing);
      expect(find.text('Unrelated'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-vault-search')));
      await tester.pumpAndSettle();
      final oldEpoch = epoch;
      expect(await invoke('search', {'epoch': epoch, 'query': 'match'}), isTrue);
      await tester.pumpAndSettle();
      tester.state<VaultPanelState>(find.byType(VaultPanel)).lockFromHeader();
      await tester.pumpAndSettle();
      expect(await invoke('search', {'epoch': oldEpoch, 'query': 'match'}), isNull);
      expect(find.byKey(ValueKey('entry-card-${favorite.id}')), findsNothing);
      expect(find.byKey(const Key('vault-master')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
