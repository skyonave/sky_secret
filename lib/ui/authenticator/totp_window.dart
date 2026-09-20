import '../shared/desktop_tooltip.dart';

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop/totp/services/totp_window_layout.dart';
import '../../core/os/windows/window/hidden_window_frame.dart';
import '../../core/os/windows/window/totp_window_region.dart';
import '../../i18n/translations.g.dart';
import '../shared/app_theme.dart';
part 'widgets/_totp_panel.dart';
part 'widgets/_totp_row.dart';
part 'widgets/_totp_page_button.dart';

class TotpWindow extends StatefulWidget {
  final WindowMethodChannel channel;

  const TotpWindow({super.key, required this.channel});

  @override
  State<TotpWindow> createState() => _TotpWindowState();

  static Future<bool> runIfNeeded() async {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) return false;
    final args = jsonDecode(controller.arguments);
    if (args is! Map || args['type'] != 'totp') return false;
    await LocaleSettings.setLocale(args['locale'] == 'en' ? AppLocale.en : AppLocale.ru);
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(TotpWindowLayout.tileWidth, TotpWindowLayout.headerHeight + TotpWindowLayout.tileHeight),
        backgroundColor: Colors.transparent,
        title: t.totpTitle,
        titleBarStyle: TitleBarStyle.hidden,
        skipTaskbar: true,
        alwaysOnTop: true,
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    runApp(TranslationProvider(child: TotpWindow(channel: WindowMethodChannel(args['channel'] as String))));
    return true;
  }
}

class _TotpWindowState extends State<TotpWindow> with WindowListener {
  List<Map> _rows = [];
  Timer? _timer;
  int? _epoch;
  int _revokedThrough = 0;
  int? _readingEpoch;
  int _lastRead = 0;
  int _page = 0;
  int _windowId = 0;
  bool _copying = false;
  String? _copied;
  String? _error;
  int _copiedUntil = 0;
  Size? _size;
  double? _scale;

  @override
  void initState() {
    super.initState();
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
            if (_epoch == null || call.arguments == _epoch) await _hide();
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
      if (await widget.channel.invokeMethod<bool>('privacy', _windowId) != true) {
        await _hide();
        return false;
      }
      await _read(epoch);
      if (_epoch != epoch) return false;
      await HiddenWindowFrame.prepare();
      if (_epoch != epoch) return false;
      await windowManager.show(inactive: true);
      if (_epoch != epoch) {
        await windowManager.hide();
        return false;
      }
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_epoch != epoch || !mounted) return;
        setState(() {});
        unawaited(_read(epoch));
      });
      return true;
    } catch (_) {
      if (_epoch == epoch) await _hide();
      return false;
    }
  }

  Future<void> _read(int epoch) async {
    final elapsed = DateTime.now().millisecondsSinceEpoch - _lastRead;
    if (_readingEpoch == epoch || _epoch != epoch || (elapsed >= 0 && elapsed < 500)) return;
    _readingEpoch = epoch;
    _lastRead = DateTime.now().millisecondsSinceEpoch;
    try {
      final data = await widget.channel.invokeMethod<Map>('read', {'epoch': epoch}).timeout(const Duration(seconds: 3));
      if (_epoch != epoch || !mounted) return;
      if (data == null) {
        await _dismiss();
        return;
      }
      final size = Size(
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
      );
      final scale = View.of(context).devicePixelRatio;
      if (_size != size || _scale != scale) {
        await windowManager.setSize(size);
        if (_epoch != epoch || !mounted) return;
        WindowRegion.setTotp(_windowId, size);
        _size = size;
        _scale = scale;
      }
      if (_epoch != epoch || !mounted) return;
      final positioned = await widget.channel.invokeMethod<bool>('position', {'epoch': epoch});
      if (_epoch != epoch || !mounted) return;
      if (positioned != true) {
        await _dismiss();
        return;
      }
      setState(() {
        _rows = (data['rows'] as List).cast<Map>();
        _page = _page.clamp(0, _maxPage);
      });
    } catch (_) {
      if (_epoch == epoch) await _dismiss();
    } finally {
      if (_readingEpoch == epoch) _readingEpoch = null;
    }
  }

  int get _slots => _size == null ? 1 : TotpWindowLayout.visibleSlots(_size!.height);
  int get _maxPage => (_rows.length - _slots).clamp(0, _rows.length);

  void _movePage(int step) {
    _activity();
    setState(() => _page = (_page + step).clamp(0, _maxPage));
  }

  Future<void> _copy(String id) async {
    final epoch = _epoch;
    if (epoch == null || _copying) return;
    setState(() => _copying = true);
    try {
      final copied = await widget.channel
          .invokeMethod<bool>('copy', {'epoch': epoch, 'id': id})
          .timeout(const Duration(seconds: 3));
      if (!mounted || _epoch != epoch) return;
      setState(() {
        _error = copied == true ? null : t.clipboardBusy;
        _copied = copied == true ? id : null;
        _copiedUntil = DateTime.now().millisecondsSinceEpoch + 1500;
      });
    } catch (_) {
      if (mounted && _epoch == epoch) setState(() => _error = t.clipboardBusy);
    } finally {
      if (mounted && _epoch == epoch) setState(() => _copying = false);
    }
  }

  void _activity() {
    if (_epoch != null) unawaited(widget.channel.invokeMethod('activity', {'epoch': _epoch}).catchError((_) => null));
  }

  @override
  void onWindowBlur() {
    if (_epoch != null) unawaited(widget.channel.invokeMethod('blur', {'epoch': _epoch}).catchError((_) => null));
  }

  @override
  void onWindowClose() => unawaited(_dismiss());

  Future<void> _dismiss() async {
    final epoch = _epoch;
    await _hide();
    try {
      await widget.channel.invokeMethod('closed', {'epoch': epoch}).timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  Future<void> _hide() async {
    _epoch = null;
    _timer?.cancel();
    _rows = [];
    _copied = null;
    _error = null;
    _copying = false;
    _lastRead = 0;
    _page = 0;
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
  void dispose() {
    _timer?.cancel();
    windowManager.removeListener(this);
    _rows = [];
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
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_dismiss())},
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _activity(),
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _movePage(event.scrollDelta.dy > 0 ? 1 : -1);
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Visibility(
              visible: _epoch != null,
              child: _TotpPanel(
                maxPage: _maxPage,
                page: _page,
                onMovePage: _movePage,
                onDismiss: _dismiss,
                rows: _rows,
                slots: _slots,
                copied: _copied,
                copiedUntil: _copiedUntil,
                copying: _copying,
                onCopy: _copy,
                error: _error,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
