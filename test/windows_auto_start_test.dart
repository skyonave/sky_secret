import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/os/windows/services/windows_auto_start.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('skysecret/auto_start');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads Windows state and confirms enable and disable', () async {
    var registered = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'set') registered = call.arguments as bool;
      return registered;
    });
    expect(await WindowsAutoStart.read(), isFalse);
    await WindowsAutoStart.setEnabled(true);
    expect(await WindowsAutoStart.read(), isTrue);
    await WindowsAutoStart.setEnabled(false);
    expect(await WindowsAutoStart.read(), isFalse);
  });

  test('read and write failures are surfaced instead of reporting success', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'ACCESS_DENIED'));
    await expectLater(WindowsAutoStart.read(), throwsA(isA<PlatformException>()));
    await expectLater(WindowsAutoStart.setEnabled(true), throwsA(isA<PlatformException>()));
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(WindowsAutoStart.read(), throwsStateError);
    await expectLater(WindowsAutoStart.setEnabled(false), throwsStateError);
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    await expectLater(WindowsAutoStart.setEnabled(true), throwsStateError);
  });
}
