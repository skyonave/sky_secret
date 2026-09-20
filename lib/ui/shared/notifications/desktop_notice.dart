import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../i18n/translations.g.dart';
import 'controllers/desktop_notice_controller.dart';

export 'controllers/desktop_notice_controller.dart' show DesktopNoticeKind;

class DesktopNoticeHost extends StatefulWidget {
  final Widget child;

  const DesktopNoticeHost({super.key, required this.child});

  static void show(
    BuildContext context,
    String message, {
    DesktopNoticeKind kind = DesktopNoticeKind.error,
  }) => context.findAncestorStateOfType<_DesktopNoticeHostState>()?._controller.show(message, kind: kind);

  static void clear(BuildContext context) =>
      context.findAncestorStateOfType<_DesktopNoticeHostState>()?._controller.clear();

  @override
  State<DesktopNoticeHost> createState() => _DesktopNoticeHostState();
}

class _DesktopNoticeHostState extends State<DesktopNoticeHost> {
  static const _channel = MethodChannel('skysecret/desktop_notice');
  final _controller = DesktopNoticeController();
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (!mounted || args is! Map || args['id'] != _revision) return;
      if (call.method == 'dismiss') _controller.clear();
      if (call.method == 'hover') _controller.setHovered(args['hovered'] == true);
    });
  }

  void _changed() {
    final notice = _controller.current;
    final revision = ++_revision;
    if (notice == null) {
      unawaited(_send('hide'));
      return;
    }
    final title = switch (notice.kind) {
      DesktopNoticeKind.error => t.noticeError,
      DesktopNoticeKind.warning => t.noticeWarning,
      DesktopNoticeKind.success => t.noticeSuccess,
      DesktopNoticeKind.information => t.noticeInformation,
    };
    unawaited(
      _send('show', {
        'id': revision,
        'title': title,
        'message': notice.message,
        'kind': notice.kind.index,
        'dismiss': t.noticeDismiss,
      }),
    );
  }

  Future<void> _send(String method, [Map<String, Object>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'desktop notification',
        ),
      );
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.dispose();
    unawaited(_send('hide'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
