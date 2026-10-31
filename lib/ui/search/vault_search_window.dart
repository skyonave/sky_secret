import '../shared/desktop_tooltip.dart';

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/os/windows/window/hidden_window_frame.dart';
import '../../core/desktop/clipboard/services/sensitive_clipboard_boundary.dart';
import '../../core/os/windows/window/totp_window_region.dart';
import '../../i18n/translations.g.dart';
import '../shared/app_theme.dart';
import '../shared/input/sensitive_text_editing.dart';

class VaultSearchWindow extends StatefulWidget {
  final WindowMethodChannel channel;
  final SensitiveClipboardBoundary clipboardBoundary;
  const VaultSearchWindow({super.key, required this.channel, required this.clipboardBoundary});
  @override
  State<VaultSearchWindow> createState() => _VaultSearchWindowState();

  static Future<bool> runIfNeeded({required SensitiveClipboardBoundary clipboardBoundary}) async {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) return false;
    final args = jsonDecode(controller.arguments);
    if (args is! Map || args['type'] != 'search') return false;
    await LocaleSettings.setLocale(args['locale'] == 'en' ? AppLocale.en : AppLocale.ru);
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(360, 64),
        backgroundColor: Colors.transparent,
        title: t.browserSearch,
        titleBarStyle: TitleBarStyle.hidden,
        skipTaskbar: true,
        alwaysOnTop: true,
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    runApp(
      TranslationProvider(
        child: VaultSearchWindow(
          channel: WindowMethodChannel(args['channel'] as String),
          clipboardBoundary: clipboardBoundary,
        ),
      ),
    );
    return true;
  }
}

class _VaultSearchWindowState extends State<VaultSearchWindow> with WindowListener {
  final _query = TextEditingController();
  final _focus = FocusNode();
  int? _epoch;
  int _revokedThrough = 0;
  int _request = 0;
  int _windowId = 0;
  bool _loading = false;
  Future<void> _layout = Future.value();
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    widget.clipboardBoundary.attach(_copyQuery);
    windowManager.addListener(this);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      _windowId = await windowManager.getId();
      WindowRegion.configureTotpFrame(_windowId);
      await widget.channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'activate':
            final args = call.arguments as Map;
            return _activate(args['epoch'] as int, args['locale'] as String);
          case 'lock':
            final epoch = call.arguments as int;
            if (epoch > _revokedThrough) _revokedThrough = epoch;
            if (_epoch == null || _epoch == epoch) await _hide();
          case 'shutdown':
            unawaited(_shutdown());
        }
        return null;
      });
      if (await widget.channel.invokeMethod<bool>('privacy', _windowId) != true) {
        await _shutdown();
        return;
      }
      await HiddenWindowFrame.prepare();
      await widget.channel.invokeMethod('ready');
    } catch (_) {
      await _shutdown();
    }
  }

  Future<bool> _activate(int epoch, String locale) async {
    await _hide();
    if (epoch <= _revokedThrough) return false;
    _epoch = epoch;
    try {
      await LocaleSettings.setLocale(locale == 'en' ? AppLocale.en : AppLocale.ru);
      if (await widget.channel.invokeMethod<bool>('privacy', _windowId) != true) return false;
      if (!mounted || _epoch != epoch) return false;
      setState(() {});
      await _resize(epoch);
      await HiddenWindowFrame.prepare();
      if (_epoch != epoch) return false;
      await windowManager.show();
      if (_epoch != epoch) {
        await windowManager.hide();
        return false;
      }
      await windowManager.focus();
      if (_epoch != epoch) return false;
      _focus.requestFocus();
      _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_check(epoch)));
      return true;
    } catch (_) {
      if (_epoch == epoch) await _hide();
      return false;
    }
  }

  Future<void> _check(int epoch) async {
    try {
      final valid = await widget.channel
          .invokeMethod<bool>('position', {'epoch': epoch})
          .timeout(const Duration(seconds: 3));
      if (_epoch == epoch && valid != true) await _hide();
    } catch (_) {
      if (_epoch == epoch) await _hide();
    }
  }

  Future<void> _resize(int epoch) {
    final previous = _layout;
    final layout = () async {
      await previous;
      if (_epoch != epoch) return;
      const size = Size(360, 64);
      await windowManager.setSize(size);
      if (_epoch != epoch) return;
      WindowRegion.setRounded(_windowId, size, 10);
      if (await widget.channel.invokeMethod<bool>('position', {'epoch': epoch}) != true && _epoch == epoch) {
        await _hide();
      }
    }();
    _layout = layout.catchError((_) {});
    return layout;
  }

  void _activity() {
    final epoch = _epoch;
    if (epoch != null) unawaited(widget.channel.invokeMethod('activity', {'epoch': epoch}).catchError((_) => null));
  }

  Future<bool> _copyQuery(String text) async {
    final epoch = _epoch;
    if (epoch == null || text.length > 256) return false;
    try {
      return await widget.channel.invokeMethod<bool>('copyQuery', {'epoch': epoch, 'text': text}) == true &&
          _epoch == epoch;
    } catch (_) {
      return false;
    }
  }

  Future<void> _changed(String query) async {
    final epoch = _epoch;
    if (epoch == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
    });
    try {
      final applied = await widget.channel
          .invokeMethod<bool>('search', {'epoch': epoch, 'query': query})
          .timeout(const Duration(seconds: 3));
      if (!mounted || _epoch != epoch || request != _request) return;
      if (applied != true) {
        await _hide();
        return;
      }
      setState(() {
        _loading = false;
      });
    } catch (_) {
      if (_epoch == epoch) await _hide();
    }
  }

  Future<void> _focusResults() async {
    final epoch = _epoch;
    if (epoch == null) return;
    try {
      await widget.channel.invokeMethod<bool>('focusResults', {'epoch': epoch});
    } catch (_) {
      if (_epoch == epoch) await _hide();
    }
  }

  Future<void> _dismiss() async {
    final epoch = _epoch;
    if (epoch != null) {
      try {
        await widget.channel.invokeMethod('closed', {'epoch': epoch});
      } catch (_) {}
    }
    if (_epoch == epoch) await _hide();
  }

  Future<void> _hide() async {
    _epoch = null;
    _request++;
    _heartbeat?.cancel();
    _query.clear();
    _loading = false;
    _focus.unfocus();
    if (mounted) setState(() {});
    await windowManager.hide();
  }

  Future<void> _shutdown() async {
    await _hide();
    await widget.channel.setMethodCallHandler(null);
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() => unawaited(_dismiss());
  @override
  void onWindowBlur() {
    final epoch = _epoch;
    if (epoch != null) unawaited(widget.channel.invokeMethod('blur', {'epoch': epoch}).catchError((_) => null));
  }

  @override
  void dispose() {
    widget.clipboardBoundary.detach(_copyQuery);
    _heartbeat?.cancel();
    windowManager.removeListener(this);
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.theme,
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_dismiss()),
      },
      child: Listener(
        onPointerDown: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Visibility(
            visible: _epoch != null,
            child: Material(
              color: AppColors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SensitiveTextEditing(
                            controller: _query,
                            enabled: true,
                            copy: _copyQuery,
                            builder: (context, menuBuilder) => TextField(
                              key: const Key('vault-search-query'),
                              controller: _query,
                              focusNode: _focus,
                              maxLength: 256,
                              enableIMEPersonalizedLearning: false,
                              autocorrect: false,
                              enableSuggestions: false,
                              contextMenuBuilder: menuBuilder,
                              onChanged: (query) => unawaited(_changed(query)),
                              onSubmitted: (_) => unawaited(_focusResults()),
                              decoration: InputDecoration(
                                hintText: t.browserSearchHint,
                                counterText: '',
                                isDense: true,
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        DesktopIconButton(
                          tooltip: t.browserCloseSearch,
                          onPressed: () => unawaited(_dismiss()),
                          padding: const EdgeInsets.all(10),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Positioned(left: 8, right: 8, bottom: 1, child: LinearProgressIndicator(minHeight: 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
