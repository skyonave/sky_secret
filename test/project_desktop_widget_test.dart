import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/i18n/translations.g.dart';
import 'package:skysecret/ui/shared/app_theme.dart';
import 'package:skysecret/ui/shared/menu/desktop_select.dart';
import 'package:skysecret/ui/shared/input/sensitive_text_editing.dart';
import 'package:skysecret/ui/vault/vault_panel.dart';

void main() {
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final fonts = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts';
    final regular = FontLoader('Segoe UI')
      ..addFont(File('$fonts/segoeui.ttf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    final mono = FontLoader('Consolas')
      ..addFont(File('$fonts/consola.ttf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([regular.load(), mono.load(), icons.load()]);
  });
  for (final locale in [AppLocale.ru, AppLocale.en]) {
    testWidgets('ENV rows and text at desktop width ${locale.languageCode}', (tester) async {
      tester.view.physicalSize = const Size(460, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await LocaleSettings.setLocale(locale);
      final capture = GlobalKey();
      String? copied;
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.theme,
            home: SensitiveClipboardScope(
              copy: (value) async {
                copied = value;
                return true;
              },
              child: RepaintBoundary(
                key: capture,
                child: VaultConfigurationForms(
                  kind: 'environment',
                  data: {
                    'name': 'Development',
                    'variables': {'TOKEN': 'synthetic', 'EMPTY': ''},
                  },
                  action: (_, _) async => null,
                ),
              ),
            ),
          ),
        ),
      );
      final name = find.byKey(const Key('variable-name')).first;
      final value = find.byKey(const Key('variable-value')).first;
      expect(tester.getTopLeft(name).dy, tester.getTopLeft(value).dy);
      expect(tester.getTopLeft(value).dx, greaterThan(tester.getTopRight(name).dx));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (capture.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/qa/project-env-${locale.languageCode}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text(t.projectEnvText));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('environment-source')), 'TOKEN="replacement"\nEMPTY=""');
      await tester.tap(find.text(t.projectEnvRows));
      await tester.pump();
      expect((tester.widget<TextField>(value)).controller!.text, 'replacement');
      await tester.tap(find.text(t.projectEnvCopy));
      await tester.pump();
      expect(copied, 'TOKEN="replacement"\nEMPTY=""');
      await tester.tap(find.text(t.projectEnvText));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('environment-source')), 'BAD="unfinished');
      await tester.tap(find.text(t.projectEnvRows));
      await tester.pump();
      expect(find.byKey(const Key('environment-source')), findsOneWidget);
      expect(find.text(t.projectEnvLineError(line: 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('desktop selector switches using inset menu and preserves field padding', (tester) async {
    var selected = 'development';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, update) => DesktopSelect<String>(
                  value: selected,
                  label: 'Environment',
                  items: const [
                    (value: 'development', label: 'Development', icon: Icons.layers_outlined),
                    (value: 'production', label: 'Production', icon: Icons.layers_outlined),
                  ],
                  onChanged: (value) => update(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final decorator = tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.decoration.contentPadding, const EdgeInsets.symmetric(horizontal: 12, vertical: 10));
    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();
    expect(selected, 'production');
    expect(find.text('Production'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('folder import offers removal only after successful import', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: VaultConfigurationForms(
          kind: 'projectImport',
          data: {
            'files': [
              {'name': '.env', 'invalid': false, 'count': 2},
            ],
          },
          action: (method, _) async {
            calls.add(method);
            return true;
          },
        ),
      ),
    );
    expect(find.text(t.projectEnvDeleteSources), findsNothing);
    await tester.tap(find.text(t.projectEnvImport));
    await tester.pump();
    expect(calls, ['import']);
    expect(find.text(t.projectEnvKeepFiles), findsOneWidget);
    expect(find.text(t.projectEnvDeleteSources), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, ['import']);
  });
  testWidgets('secrets show only populated predefined sections, values remain in owner', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: VaultConfigurationForms(
          kind: 'projectSecrets',
          data: {'title': 'Synthetic project'},
          action: (method, _) async => method == 'state'
              ? {
                  'busy': false,
                  'rows': [
                    {
                      'id': 'env',
                      'title': 'Development',
                      'kind': 'environment',
                      'keys': ['TOKEN', 'EMPTY'],
                    },
                    {
                      'id': 'file',
                      'title': 'test.txt',
                      'kind': 'file',
                      'password': false,
                      'username': false,
                      'notes': false,
                      'totp': false,
                    },
                  ],
                }
              : true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(t.projectEnvironments), findsOneWidget);
    expect(find.text(t.projectSecretFiles), findsOneWidget);
    expect(find.text(t.projectSecretAccounts), findsNothing);
    expect(find.text('SSH'), findsNothing);
    expect(find.text('TOTP'), findsNothing);
    expect(find.text('TOKEN = ••••••••'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ENV eye reveals on demand, conceals and rejects late values after a context change', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    var selected = 'development';
    var busy = false;
    var revision = 1;
    Completer<String>? pending;
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: VaultConfigurationForms(
          kind: 'projectSecrets',
          data: {'title': 'Synthetic project'},
          action: (method, arguments) async {
            calls.add(method);
            if (method == 'state') {
              return {
                'busy': busy,
                'revision': revision,
                'rows': [
                  {
                    'id': selected,
                    'title': selected,
                    'kind': 'environment',
                    'keys': ['TOKEN'],
                  },
                ],
              };
            }
            if (method == 'reveal') return pending == null ? 'synthetic value' : pending.future;
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    expect(calls, ['state']);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('TOKEN = synthetic value'), findsOneWidget);
    expect(calls.where((c) => c == 'copyField'), isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TOKEN = synthetic value'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(find.text('TOKEN = ••••••••'), findsOneWidget);
    pending = Completer<String>();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    selected = 'production';
    await tester.pump(const Duration(milliseconds: 400));
    pending.complete('stale synthetic');
    await tester.pump();
    expect(find.textContaining('stale synthetic'), findsNothing);
    pending = null;
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    revision++;
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TOKEN = ••••••••'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    busy = true;
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TOKEN = synthetic value'), findsNothing);
    expect(find.text('TOKEN = ••••••••'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
