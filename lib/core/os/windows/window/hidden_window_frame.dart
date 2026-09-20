import 'package:flutter/scheduler.dart';

abstract final class HiddenWindowFrame {
  static Future<void> prepare() {
    final binding = SchedulerBinding.instance;
    binding.scheduleWarmUpFrame();
    return binding.endOfFrame;
  }
}
