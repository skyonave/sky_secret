import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/desktop/drag/controllers/secret_drag_controller.dart';

void main() {
  const labels = {
    'hover': 'Hover',
    'login': 'Login',
    'password': 'Password',
    'pair': 'Login and password',
    'missingLogin': 'No login',
    'missingPassword': 'No password',
  };
  VaultEntry entry() => VaultEntry.create(title: 'Synthetic', username: 'user@example.test', password: 'synthetic 🧪');

  test('transport contains only protected credentials and wipes both copies', () async {
    final original = entry();
    late Uint8List username;
    late Uint8List password;
    final active = <bool>[];
    final controller = SecretDragController(
      onActiveChanged: active.add,
      invoke: (method, arguments) async {
        if (method == 'prepare') return 12;
        final values = arguments as Map;
        expect(
          values.keys,
          unorderedEquals([
            'id',
            'epoch',
            'title',
            'hover',
            'login',
            'passwordLabel',
            'pairLabel',
            'missingLogin',
            'missingPassword',
            'usernameSize',
            'username',
            'passwordSize',
            'password',
          ]),
        );
        expect(values['epoch'], 12);
        expect(values['title'], 'Synthetic');
        expect(values['login'], labels['login']);
        expect(values['passwordLabel'], labels['password']);
        expect(values['pairLabel'], labels['pair']);
        expect(values['usernameSize'], utf8.encode(original.username).length);
        expect(values['passwordSize'], utf8.encode(original.password).length);
        username = values['username'] as Uint8List;
        password = values['password'] as Uint8List;
        expect(username, original.copyProtectedUsername().data);
        expect(password, original.copyProtectedPassword().data);
        expect(password.take(4), isNot(utf8.encode(original.password).take(4)));
        return 'filled';
      },
    );
    expect(await controller.start(labels: labels, entry: original, allowed: () => true), SecretDragResult.filled);
    expect(username.every((value) => value == 0), isTrue);
    expect(password.every((value) => value == 0), isTrue);
    expect(original.password, 'synthetic 🧪');
    expect(active, [true, false]);
  });

  test('locking during prepare never sends credentials', () async {
    final ready = Completer<Object?>();
    var allowed = true;
    final controller = SecretDragController(
      invoke: (method, _) {
        expect(method, 'prepare');
        return ready.future;
      },
    );
    final pending = controller.start(labels: labels, entry: entry(), allowed: () => allowed);
    allowed = false;
    ready.complete(1);
    expect(await pending, SecretDragResult.cancelled);
  });

  test('cancelled old completion cannot end a replacement gesture', () async {
    final started = Completer<void>();
    final firstResult = Completer<Object?>();
    final secondResult = Completer<Object?>();
    var starts = 0;
    final controller = SecretDragController(
      invoke: (method, _) async {
        if (method == 'prepare') return 1;
        if (method == 'cancel') return null;
        if (starts++ == 0) {
          started.complete();
          return firstResult.future;
        }
        return secondResult.future;
      },
    );
    final first = controller.start(labels: labels, entry: entry(), allowed: () => true);
    await started.future;
    controller.cancel();
    final second = controller.start(labels: labels, entry: entry(), allowed: () => true);
    firstResult.complete('filled');
    expect(await first, SecretDragResult.cancelled);
    expect(controller.active, isTrue);
    secondResult.complete('unsupported');
    expect(await second, SecretDragResult.unsupported);
    expect(controller.active, isFalse);
  });

  test('native errors wipe both buffers and release the active state', () async {
    late Map values;
    final controller = SecretDragController(
      invoke: (method, arguments) async {
        if (method == 'prepare') return 1;
        values = arguments as Map;
        throw StateError('Synthetic failure');
      },
    );
    await expectLater(controller.start(labels: labels, entry: entry(), allowed: () => true), throwsStateError);
    for (final key in ['username', 'password']) {
      expect((values[key] as Uint8List).every((value) => value == 0), isTrue);
    }
    expect(controller.active, isFalse);
  });

  test('dispose revokes preparation and rejects future gestures', () async {
    final ready = Completer<Object?>();
    final methods = <String>[];
    final controller = SecretDragController(
      invoke: (method, _) async {
        methods.add(method);
        return method == 'prepare' ? ready.future : null;
      },
    );
    final pending = controller.start(labels: labels, entry: entry(), allowed: () => true);
    controller.dispose();
    ready.complete(1);
    expect(await pending, SecretDragResult.cancelled);
    expect(await controller.start(labels: labels, entry: entry(), allowed: () => true), SecretDragResult.cancelled);
    expect(methods, ['prepare', 'cancel']);
  });

  test('files and revoked authorization never reach the native bridge', () async {
    final controller = SecretDragController(invoke: (_, _) async => fail('Unexpected native call'));
    expect(await controller.start(labels: labels, entry: entry(), allowed: () => false), SecretDragResult.cancelled);
    final file = VaultEntry.file(VaultAttachment.create('synthetic.txt', []));
    expect(await controller.start(labels: labels, entry: file, allowed: () => true), SecretDragResult.cancelled);
  });

  for (final native in [
    'partial',
    'unsupported',
    'targetLost',
    'targetChanged',
    'missingValue',
    'failed',
    'cancelled',
    'unknown',
  ]) {
    test('native result $native remains distinguishable', () async {
      final controller = SecretDragController(invoke: (method, _) async => method == 'prepare' ? 1 : native);
      final expected = SecretDragResult.values.where((value) => value.name == native).firstOrNull;
      expect(
        await controller.start(labels: labels, entry: entry(), allowed: () => true),
        expected ?? SecretDragResult.failed,
      );
    });
  }
}
