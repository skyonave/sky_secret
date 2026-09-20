import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/startup/controllers/startup_progress.dart';

void main() {
  test('readiness waits for every stage and completes once', () {
    final results = <bool>[];
    final progress = StartupProgress(stages: {'desktop', 'forms', 'search'}, onComplete: results.add);
    progress.finish('forms', success: true);
    progress.finish('forms', success: false);
    progress.finish('unrelated', success: false);
    progress.finish('desktop', success: true);
    expect(results, isEmpty);
    progress.finish('search', success: true);
    progress.finish('search', success: false);
    expect(results, [true]);
  });
  test('failed preload cannot produce green readiness', () {
    final results = <bool>[];
    final progress = StartupProgress(stages: {'forms', 'desktop'}, onComplete: results.add);
    progress.finish('forms', success: false);
    expect(results, isEmpty);
    progress.finish('desktop', success: true);
    expect(results, [false]);
  });
}
