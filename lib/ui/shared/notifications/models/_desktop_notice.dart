part of '../controllers/desktop_notice_controller.dart';

enum DesktopNoticeKind { success, information, warning, error }

class DesktopNotice {
  final String message;
  final DesktopNoticeKind kind;

  const DesktopNotice(this.message, this.kind);

  Duration get duration => switch (kind) {
    DesktopNoticeKind.success || DesktopNoticeKind.information => const Duration(seconds: 4),
    DesktopNoticeKind.warning || DesktopNoticeKind.error => const Duration(seconds: 4),
  };
}
