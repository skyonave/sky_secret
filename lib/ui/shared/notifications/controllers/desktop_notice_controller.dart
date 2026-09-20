import 'dart:async';

import 'package:flutter/foundation.dart';
part '../models/_desktop_notice.dart';

class DesktopNoticeController extends ChangeNotifier {
  DesktopNotice? _current;
  Timer? _timer;
  bool _hovered = false;
  bool _focused = false;

  DesktopNotice? get current => _current;

  void show(String message, {DesktopNoticeKind kind = DesktopNoticeKind.error}) {
    final readingProblem = _current?.kind == DesktopNoticeKind.error || _current?.kind == DesktopNoticeKind.warning;
    if (readingProblem && (kind == DesktopNoticeKind.success || kind == DesktopNoticeKind.information)) return;
    _current = DesktopNotice(message, kind);
    _restartTimer();
    notifyListeners();
  }

  void setHovered(bool value) {
    _hovered = value;
    _restartTimer();
  }

  void setFocused(bool value) {
    _focused = value;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_current == null || _hovered || _focused) return;
    _timer = Timer(_current!.duration, clear);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _current = null;
    _hovered = false;
    _focused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _current = null;
    super.dispose();
  }
}
