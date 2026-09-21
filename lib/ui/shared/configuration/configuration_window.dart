import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/desktop/clipboard/services/sensitive_clipboard_boundary.dart';
import '../../../core/desktop/configuration/controllers/configuration_windows.dart';
import '../../../core/os/windows/window/hidden_window_frame.dart';
import '../../../i18n/translations.g.dart';
import '../../vault/vault_panel.dart';
import '../app_theme.dart';
import '../input/sensitive_text_editing.dart';
import '../notifications/desktop_notice.dart';

class ConfigurationWindow extends StatefulWidget {
  final WindowMethodChannel channel;
  final SensitiveClipboardBoundary clipboard;

  const ConfigurationWindow({super.key, required this.channel, required this.clipboard});

  static Future<bool> runIfNeeded(SensitiveClipboardBoundary clipboard) async {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isEmpty) return false;
    final args = jsonDecode(controller.arguments);
    if (args is! Map || args['type'] != 'configuration') return false;
    ConfigurationWindows.isChild = true;
    await LocaleSettings.setLocale(args['locale'] == 'en' ? AppLocale.en : AppLocale.ru);
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(460, 600),
        skipTaskbar: true,
        backgroundColor: Color(0xFF0B131B),
        alwaysOnTop: true,
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    runApp(
      TranslationProvider(
        child: ConfigurationWindow(
          channel: WindowMethodChannel(args['channel'] as String),
          clipboard: clipboard,
        ),
      ),
    );
    return true;
  }

  @override
  State<ConfigurationWindow> createState() => _ConfigurationWindowState();
}

class _ConfigurationWindowState extends State<ConfigurationWindow> with WindowListener {
  GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  WindowMethodChannel? _session;
  Future<void>? _closing;
  Timer? _timer;
  bool _closed = true;
  bool _pinging = false;
  bool _shutdownRequested = false;
  bool _usable = true;
  DateTime _activityAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.clipboard.attach(_copy);
    HardwareKeyboard.instance.addHandler(_key);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      await widget.channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'activate':
            final args = call.arguments as Map;
            return _activate(args['channel'] as String, args['locale'] as String);
          case 'reset':
            await _close(sendResult: false);
            return _usable;
          case 'shutdown':
            unawaited(_shutdown());
        }
        return null;
      });
      await HiddenWindowFrame.prepare();
      await widget.channel.invokeMethod('ready');
    } catch (_) {
      await _shutdown();
    }
  }

  Future<bool> _copy(String text) async {
    final session = _session;
    if (_closed || session == null) return false;
    return await session.invokeMethod<bool>('copy', text) == true;
  }

  bool _key(KeyEvent event) {
    _activity();
    return false;
  }

  void _activity() {
    if (_closed || DateTime.now().difference(_activityAt).inMilliseconds < 500) return;
    _activityAt = DateTime.now();
    unawaited(_session?.invokeMethod('activity').catchError((_) => null));
  }

  Future<bool> _activate(String channel, String locale) async {
    if (_shutdownRequested || !_usable || !_closed || _session != null) return false;
    await _closing;
    if (_shutdownRequested) return false;
    final session = WindowMethodChannel(channel);
    _session = session;
    _closed = false;
    bool current() => mounted && !_closed && identical(_session, session);
    try {
      await LocaleSettings.setLocale(locale == 'en' ? AppLocale.en : AppLocale.ru);
      await session.setMethodCallHandler((call) async {
        if (call.method == 'close' && current()) unawaited(_close(sendResult: false));
        return null;
      });
      if (!current()) return false;
      final connected = await session
          .invokeMethod<bool>('connect', await windowManager.getId())
          .timeout(const Duration(seconds: 5));
      if (!current()) return false;
      if (connected != true) {
        await _close(sendResult: false);
        return false;
      }
      final payload = await session.invokeMethod<Map>('read').timeout(const Duration(seconds: 5));
      if (!current() || payload == null) {
        await _close(sendResult: false);
        return false;
      }
      final kind = payload['kind'] as String;
      final page = VaultConfigurationForms(
        kind: kind,
        data: Map<String, dynamic>.from(payload['data'] as Map),
        action: (method, arguments) async => current() ? await session.invokeMethod(method, arguments) : null,
      );
      setState(() {});
      final result = _navigator.currentState!.push<dynamic>(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => page,
        ),
      );
      unawaited(
        result.then((value) async {
          if (current()) await _close(result: VaultConfigurationForms.encode(kind, value));
        }),
      );
      await HiddenWindowFrame.prepare();
      if (!current()) return false;
      if (await session.invokeMethod<bool>('alive').timeout(const Duration(seconds: 3)) != true) {
        await _close(sendResult: false);
        return false;
      }
      if (!current()) return false;
      await windowManager.show(inactive: payload['companion'] == true);
      if (!current()) {
        await windowManager.hide();
        return false;
      }
      if (payload['companion'] != true) await windowManager.focus();
      if (!current()) return false;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _ping(session));
      return true;
    } catch (_) {
      if (identical(_session, session)) await _close(sendResult: false);
      return false;
    }
  }

  Future<void> _ping(WindowMethodChannel session) async {
    if (_pinging || _closed) return;
    _pinging = true;
    try {
      if (await session.invokeMethod<bool>('alive').timeout(const Duration(seconds: 3)) != true &&
          identical(_session, session)) {
        await _close(sendResult: false);
      }
    } catch (_) {
      if (identical(_session, session)) await _close(sendResult: false);
    } finally {
      _pinging = false;
    }
  }

  Future<void> _close({dynamic result, bool sendResult = true}) {
    if (_closed) return _closing ?? Future.value();
    _closed = true;
    _timer?.cancel();
    final session = _session;
    _session = null;
    final closing = _clear(session, result, sendResult);
    _closing = closing;
    return closing;
  }

  Future<void> _clear(WindowMethodChannel? session, dynamic result, bool sendResult) async {
    try {
      try {
        if (mounted) {
          final context = _navigator.currentContext;
          if (context != null && context.mounted) DesktopNoticeHost.clear(context);
          setState(() => _navigator = GlobalKey<NavigatorState>());
          await HiddenWindowFrame.prepare();
        }
      } catch (_) {
        _usable = false;
      }
      if (sendResult) {
        try {
          await session?.invokeMethod('closing').timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      try {
        await windowManager.hide();
      } catch (_) {
        _usable = false;
      }
      if (sendResult) {
        await session?.invokeMethod('complete', result).timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      _usable = false;
    } finally {
      try {
        await session?.setMethodCallHandler(null);
      } catch (_) {
        _usable = false;
      } finally {
        _closing = null;
      }
    }
  }

  Future<void> _shutdown() async {
    _shutdownRequested = true;
    await _close(sendResult: false);
    await widget.channel.setMethodCallHandler(null);
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() => unawaited(_close());

  @override
  void onWindowBlur() {
    if (_closed) return;
    unawaited(_session?.invokeMethod('blur').catchError((_) => null));
  }

  @override
  void dispose() {
    _timer?.cancel();
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_key);
    widget.clipboard.detach(_copy);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    theme: AppTheme.theme,
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    builder: (context, child) => DesktopNoticeHost(
      child: SensitiveClipboardScope(
        copy: _copy,
        child: Listener(onPointerDown: (_) => _activity(), child: child!),
      ),
    ),
    home: const Scaffold(),
  );
}
