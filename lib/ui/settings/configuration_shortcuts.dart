import 'dart:async';

import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/desktop/desktop_actions.dart';

class ConfigurationShortcuts extends DesktopActions {
  final Future<dynamic> Function(String, dynamic) action;
  final HotKey _shortcut;
  final HotKey _search;

  ConfigurationShortcuts(Map<String, dynamic> data, this.action)
    : _shortcut = HotKey.fromJson(Map<String, dynamic>.from(data['shortcut'] as Map)),
      _search = HotKey.fromJson(Map<String, dynamic>.from(data['search'] as Map));

  @override
  String? get notice => null;
  @override
  HotKey get shortcut => _shortcut;
  @override
  HotKey get searchShortcut => _search;
  @override
  Future<void> hide() async {}
  @override
  Future<void> drag() async {}
  @override
  void setShortcutCapture(bool capturing) => unawaited(action('capture', capturing));
  @override
  Future<String?> updateShortcut(HotKey shortcut) async => await action('shortcut', shortcut.toJson()) as String?;
  @override
  Future<String?> updateSearchShortcut(HotKey candidate) async => await action('search', candidate.toJson()) as String?;
}
