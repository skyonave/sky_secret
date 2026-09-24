import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/configuration/controllers/configuration_windows.dart';
import 'package:skysecret/core/os/windows/window/window_privacy.dart';

class Transport {
  static const windows = MethodChannel('mixin.one/desktop_multi_window');
  static const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  static const placement = MethodChannel('skysecret/companion');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = Completer<void>();
  final registered = Completer<void>();
  final events = <String>[];
  final placements = <MethodCall>[];
  final sessions = <String>[];
  Completer<void>? registration;
  Completer<String>? creation;
  Completer<void>? reset;
  Completer<void>? activation;
  bool failReset = false;
  int count = 0;
  String? session;
  Map? payload;

  void attach() {
    messenger.setMockMethodCallHandler(placement, (call) async {
      placements.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(windows, (call) async {
      events.add(call.method);
      if (call.method == 'createWindow') {
        count++;
        final args = jsonDecode((call.arguments as Map)['arguments'] as String) as Map;
        expect((call.arguments as Map)['hiddenAtLaunch'], isTrue);
        expect(args.keys, unorderedEquals(['type', 'channel', 'locale']));
        if (!created.isCompleted) created.complete();
        final id = creation == null ? 'window-$count' : await creation!.future;
        await fromChild(args['channel'] as String, 'ready');
        return id;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'registerMethodHandler') {
        events.add('register');
        if (!registered.isCompleted) registered.complete();
        await registration?.future;
      } else if (call.method == 'unregisterMethodHandler') {
        events.add('unregister');
      } else if (call.method == 'invokeMethod') {
        final args = call.arguments as Map;
        final method = args['method'] as String;
        events.add(method);
        if (method == 'activate') {
          final channel = (args['arguments'] as Map)['channel'] as String;
          session = channel;
          sessions.add(channel);
          await activation?.future;
          if (await fromChild(channel, 'connect', 42) != true) return false;
          payload = await fromChild(channel, 'read') as Map?;
          return payload != null;
        }
        if (method == 'reset') {
          await reset?.future;
          if (failReset) throw PlatformException(code: 'WINDOW_GONE');
          payload = null;
          return true;
        }
      }
      return null;
    });
  }

  Future<dynamic> fromChild(String channel, String method, [dynamic arguments]) async {
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channels.name,
      channels.codec.encodeMethodCall(
        MethodCall('methodCall', {'channel': channel, 'method': method, 'arguments': arguments}),
      ),
      reply.complete,
    );
    return channels.codec.decodeEnvelope((await reply.future)!);
  }

  Future<void> until(bool Function() predicate) async {
    for (var i = 0; i < 100; i++) {
      if (predicate()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('Missing expected state: $events');
  }

  void detach() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
    messenger.setMockMethodCallHandler(placement, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Transport transport;
  setUp(() {
    ConfigurationWindows.registerWindow = (_) => true;
    transport = Transport()..attach();
  });
  tearDown(() async {
    expect(ConfigurationWindows.isOpen, isFalse);
    expect(ConfigurationWindows.opened.value, isFalse);
    await ConfigurationWindows.dispose();
    ConfigurationWindows.registerWindow = WindowPrivacy.registerWindow;
    ConfigurationWindows.copy = null;
    ConfigurationWindows.clearClipboard = null;
    transport.detach();
  });

  test('invalid session creates nothing', () async {
    expect(await ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => false), isNull);
    expect(transport.events, isEmpty);
  });

  test('normal close returns focus before completion but revoked close cannot do so', () async {
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.until(() => transport.payload != null);
    expect(await transport.fromChild(transport.session!, 'closing'), isTrue);
    expect(transport.placements.last.method, 'returnFocus');
    expect(transport.placements.last.arguments, {'window': 42});
    ConfigurationWindows.closeAll();
    final count = transport.placements.length;
    expect(await transport.fromChild(transport.session!, 'closing'), isNull);
    expect(transport.placements.length, count);
    await result;
  });

  test('preload remains hidden; repeated forms reuse an engine with fresh channels', () async {
    await ConfigurationWindows.prepare('en');
    expect(ConfigurationWindows.isOpen, isFalse);
    expect(transport.events, isNot(contains('activate')));
    for (var i = 0; i < 3; i++) {
      final result = ConfigurationWindows.open(kind: 'name', locale: 'en', data: {'value': '$i'}, isValid: () => true);
      await transport.until(() => transport.payload != null);
      expect(transport.payload!['data'], {'value': '$i'});
      expect(await transport.fromChild(transport.session!, 'read'), isNull);
      await transport.fromChild(transport.session!, 'complete', '$i');
      expect(await result, '$i');
      expect(transport.payload, isNull);
    }
    expect(transport.count, 1);
    expect(transport.sessions.toSet().length, 3);
    expect(transport.events, isNot(contains('shutdown')));
    expect(transport.events, isNot(contains('window_show')));
  });

  test('revocation during registration prevents creation', () async {
    transport.registration = Completer<void>();
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.registered.future;
    ConfigurationWindows.closeAll();
    transport.registration!.complete();
    expect(await result, isNull);
    expect(transport.events, ['register', 'unregister']);
  });

  test('revocation during creation prevents activation and clears eventual engine', () async {
    transport.creation = Completer<String>();
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.created.future;
    ConfigurationWindows.closeAll();
    ConfigurationWindows.closeAll();
    transport.creation!.complete('window');
    expect(await result, isNull);
    expect(transport.events, isNot(contains('activate')));
    expect(transport.events.where((e) => e == 'reset').length, 1);
  });

  test('revocation during activation denies late reads and connect', () async {
    await ConfigurationWindows.prepare('en');
    transport.activation = Completer<void>();
    final result = ConfigurationWindows.open(
      kind: 'entry',
      locale: 'en',
      data: {'value': 'test-only'},
      isValid: () => true,
    );
    await transport.until(() => transport.session != null);
    ConfigurationWindows.closeAll();
    expect(await transport.fromChild(transport.session!, 'read'), isNull);
    transport.activation!.complete();
    expect(await result, isNull);
    expect(transport.payload, isNull);
  });

  test('completion waits until reset acknowledges data removal', () async {
    transport.reset = Completer<void>();
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.until(() => transport.payload != null);
    var finished = false;
    unawaited(result.then((_) => finished = true));
    await transport.fromChild(transport.session!, 'complete');
    await transport.until(() => transport.events.contains('reset'));
    expect(finished, isFalse);
    transport.reset!.complete();
    await result;
    expect(finished, isTrue);
  });

  test('creation failure releases handlers and permits retry', () async {
    transport.creation = Completer<String>();
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    final assertion = expectLater(result, throwsA(isA<PlatformException>()));
    await transport.created.future;
    transport.creation!.completeError(PlatformException(code: 'CREATION_FAILED'));
    await assertion;
    transport.creation = null;
    await ConfigurationWindows.prepare('en');
    expect(transport.count, 2);
  });

  test('failed reset destroys host instead of reusing uncleared state', () async {
    transport.failReset = true;
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.until(() => transport.payload != null);
    await transport.fromChild(transport.session!, 'complete');
    await result;
    expect(transport.events, contains('shutdown'));
    transport.failReset = false;
    await ConfigurationWindows.prepare('en');
    expect(transport.count, 2);
  });

  test('revoked copy clears late clipboard write', () async {
    final copying = Completer<bool>();
    var cleared = false;
    ConfigurationWindows.copy = (_) => copying.future;
    ConfigurationWindows.clearClipboard = () async => cleared = true;
    final result = ConfigurationWindows.open(kind: 'entry', locale: 'en', isValid: () => true);
    await transport.until(() => transport.payload != null);
    final response = transport.fromChild(transport.session!, 'copy', 'test-only');
    await Future<void>.delayed(Duration.zero);
    ConfigurationWindows.closeAll();
    copying.complete(true);
    expect(await response, isFalse);
    await result;
    expect(cleared, isTrue);
  });

  test('privacy failure never exposes form payload', () async {
    ConfigurationWindows.registerWindow = (_) => false;
    expect(
      await ConfigurationWindows.open(
        kind: 'entry',
        locale: 'en',
        data: {'value': 'test-only'},
        isValid: () => true,
      ),
      isNull,
    );
    expect(transport.payload, isNull);
  });

  test('disposal during an active form does not return its engine to the pool', () async {
    final result = ConfigurationWindows.open(kind: 'name', locale: 'en', isValid: () => true);
    await transport.until(() => transport.payload != null);
    await ConfigurationWindows.dispose();
    await result;
    expect(transport.events, contains('shutdown'));
    await ConfigurationWindows.prepare('en');
    expect(transport.count, 2);
  });
}
