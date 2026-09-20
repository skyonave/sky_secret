import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/shared/notifications/controllers/desktop_notice_controller.dart';

class _NoticeTimer implements Timer {
  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  _NoticeTimer(this.duration, this.callback);

  void fire() {
    if (_active == false) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

void main() {
  late DesktopNoticeController controller;
  late List<_NoticeTimer> timers;
  late Zone zone;

  setUp(() {
    controller = DesktopNoticeController();
    timers = [];
    zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = _NoticeTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  });

  tearDown(() => controller.dispose());

  test('errors and successful results expire after four seconds', () {
    zone.run(() {
      controller.show('Saved', kind: DesktopNoticeKind.success);
      expect(timers.last.duration, const Duration(seconds: 4));
      timers.last.fire();
      expect(controller.current, isNull);
      controller.show('Could not save');
      expect(timers.last.duration, const Duration(seconds: 4));
      timers.last.fire();
      expect(controller.current, isNull);
    });
  });

  test('success cannot replace an unread problem, another problem can', () {
    zone.run(() {
      controller.show('Could not save');
      final deadline = timers.last;
      controller.show('Copied', kind: DesktopNoticeKind.success);
      expect(controller.current!.message, 'Could not save');
      expect(timers.last, same(deadline));
      controller.show('Cleanup incomplete', kind: DesktopNoticeKind.warning);
      expect(controller.current!.message, 'Cleanup incomplete');
      expect(deadline.isActive, isFalse);
    });
  });

  test('hover and keyboard focus both keep a notice available', () {
    zone.run(() {
      controller.show('Could not save');
      controller.setHovered(true);
      timers.last.fire();
      expect(controller.current, isNotNull);
      controller.setFocused(true);
      controller.setHovered(false);
      expect(timers.where((timer) => timer.isActive), isEmpty);
      controller.setFocused(false);
      expect(timers.last.duration, const Duration(seconds: 4));
      expect(timers.last.isActive, isTrue);
      timers.last.fire();
      expect(controller.current, isNull);
    });
  });

  test('old deadline does not dismiss a replacement', () {
    zone.run(() {
      controller.show('First error');
      final old = timers.last;
      controller.show('Second error');
      old.fire();
      expect(controller.current!.message, 'Second error');
    });
  });

  test('clear on hide or lock cancels expiry and resets hover state', () {
    zone.run(() {
      controller.show('Old session');
      controller.setHovered(true);
      controller.clear();
      expect(controller.current, isNull);
      controller.show('New session');
      expect(timers.last.isActive, isTrue);
      for (final timer in timers.take(timers.length - 1)) {
        timer.fire();
      }
      expect(controller.current!.message, 'New session');
    });
  });

  test('disposal cancels pending callbacks', () {
    zone.run(() {
      final closing = DesktopNoticeController();
      closing.show('Closing');
      closing.dispose();
      expect(timers.last.isActive, isFalse);
      timers.last.fire();
      expect(closing.current, isNull);
    });
  });
}
