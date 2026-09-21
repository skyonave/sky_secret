import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/projects/controllers/project_launch_controller.dart';
import 'package:skysecret/core/projects/models/project_launch_profile.dart';
import 'package:skysecret/core/projects/repositories/project_launch_preferences.dart';

import 'vault_sections_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const password = 'Synthetic environment test phrase 942!';
  final profile = ProjectLaunchProfile(
    executable: r'C:\runtime\node.exe',
    directory: r'C:\repo',
    arguments: ['server.js'],
  );
  VaultEntry environment() => VaultEntry(
    id: 'synthetic-environment',
    title: 'Development',
    username: '',
    password: '',
    notes: ProjectEnvironment({'API_TOKEN': 'synthetic-token', 'MULTILINE': 'line1\nline2', 'EMPTY': ''}).encode(),
    kind: VaultEntryKind.environment,
  );

  test('environment validation rejects ambiguous names, NUL, oversized and malformed payloads', () {
    for (final variables in [
      {'TOKEN': 'a', 'token': 'b'},
      {'1KEY': 'value'},
      {'A=B': 'value'},
      {'OK': 'a\u0000b'},
      {'OK': 'x' * 24000},
      {for (var i = 0; i < 129; i++) 'KEY_$i': ''},
    ]) {
      expect(() => ProjectEnvironment(variables), throwsFormatException);
    }
    for (final source in ['{}', '{"version":2,"variables":{}}', '{"version":1,"variables":{"A":1}}']) {
      expect(() => ProjectEnvironment.decode(source), throwsFormatException);
    }
    final value = ProjectEnvironment({'UNICODE': 'Тест 😀', 'EMPTY': '', 'MULTI': 'a\nb'});
    expect(ProjectEnvironment.decode(value.encode()).variables, value.variables);
    expect(() => value.variables['NEW'] = 'value', throwsUnsupportedError);
  });

  for (final schema in [8, 9, 10]) {
    test('schema$schema entries and metadata survive environment upgrade, reopen and password rotation', () async {
      final entry = VaultEntry.create(
        title: 'Legacy',
        username: 'Synthetic user',
        password: 'Synthetic password',
        notes: 'Original notes',
      ).withFavorite(true);
      final project = VaultProject(id: 'project', vaultId: 'a' * 32, lineage: 'b' * 32, name: 'Project');
      final bytes = await fixture({
        'schemaVersion': schema,
        'revision': VaultRevision('c' * 32, {}).toJson(),
        'name': 'Original',
        'folders': <Object>[],
        'entries': [entry.toJson()],
        if (schema == 10) 'projects': [project.toJson()],
      }, password: password);
      final session = await VaultCipher.unlock(bytes, password);
      addTearDown(session.lock);
      final encoded = await session.encrypt([...session.entries, environment()]);
      final reopened = await VaultCipher.unlock(encoded, password);
      addTearDown(reopened.lock);
      expect(reopened.entries.first.toJson(), entry.toJson());
      expect(reopened.entries.last.kind, VaultEntryKind.environment);
      expect(ProjectEnvironment.decode(reopened.entries.last.notes).variables['API_TOKEN'], 'synthetic-token');
      expect(reopened.projects.map((p) => p.toJson()), schema == 10 ? [project.toJson()] : isEmpty);
      final rotated = await reopened.changePassword('Synthetic replacement phrase 942!');
      addTearDown(rotated.lock);
      final finalOpen = await VaultCipher.unlock(rotated.persistedBytes, 'Synthetic replacement phrase 942!');
      addTearDown(finalOpen.lock);
      expect(finalOpen.entries.map((e) => e.toJson()), reopened.entries.map((e) => e.toJson()));
    });
  }

  test('environment kind is rejected in an older schema', () async {
    final bytes = await fixture({
      'schemaVersion': 10,
      'name': 'Synthetic older vault',
      'revision': VaultRevision('c' * 32, {}).toJson(),
      'folders': <Object>[],
      'entries': [environment().toJson()],
      'projects': <Object>[],
    }, password: password);
    await expectLater(VaultCipher.unlock(bytes, password), throwsA(isA<VaultFormatException>()));
  });

  test('concurrent environment edits preserve both secret variants after merge and reopen', () async {
    final root = await VaultCipher.create(password);
    addTearDown(root.lock);
    final base = await root.openRevision(await root.encrypt([environment()]));
    VaultEntry variant(String value) => VaultEntry(
      id: environment().id,
      title: 'Development',
      username: '',
      password: '',
      notes: ProjectEnvironment({'API_TOKEN': value}).encode(),
      kind: VaultEntryKind.environment,
    );
    final left = await root.openRevision(await root.encrypt([variant('synthetic-left')]));
    final right = await root.openRevision(await root.encrypt([variant('synthetic-right')]));
    final merged = await VaultMerge.combine(base, left, right);
    expect(merged.conflicts, 1);
    final reopened = await root.openRevision(await root.encrypt(merged.entries));
    expect(reopened.entries.every((entry) => entry.isEnvironment && entry.conflictOf != null), isTrue);
    expect(reopened.entries.map((entry) => ProjectEnvironment.decode(entry.notes).variables['API_TOKEN']).toSet(), {
      'synthetic-left',
      'synthetic-right',
    });
  });

  test('launch profiles reject relative paths, scripts and secret arguments', () {
    for (final executable in ['node.exe', r'C:node.exe', r'C:\repo\run.cmd', r'\\server\share\app.exe']) {
      expect(
        () => ProjectLaunchProfile(executable: executable, directory: r'C:\repo', arguments: []),
        throwsFormatException,
      );
    }
    final bad = ProjectLaunchProfile(
      executable: r'C:\runtime\node.exe',
      directory: r'C:\repo',
      arguments: ['--token=synthetic-token'],
    );
    expect(() => bad.checkSecrets(['synthetic-token']), throwsFormatException);
    profile.checkSecrets(['synthetic-token']);
  });

  test('local launch settings serialize concurrent writes without storing environment values', () async {
    final directory = await Directory.systemTemp.createTemp('skysecret-launch-unit-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/launch.dpapi');
    var encrypted = 0;
    final repository = ProjectLaunchPreferences(
      file: file,
      protect: (bytes, {decrypt = false}) {
        if (!decrypt) encrypted++;
        return Uint8List.fromList(bytes.map((byte) => byte ^ 0x5a).toList());
      },
    );
    await Future.wait([repository.save('a', profile), repository.save('b', profile)]);
    expect(encrypted, 2);
    expect((await repository.read('a'))!.toJson(), profile.toJson());
    expect((await repository.read('b'))!.toJson(), profile.toJson());
    expect(await repository.read('missing'), isNull);
    expect(profile.toJson().keys, ['executable', 'directory', 'arguments']);
  });

  test('connected folder persists separately from environment launch settings', () async {
    final directory = await Directory.systemTemp.createTemp('project-folder-synthetic-');
    addTearDown(() => directory.delete(recursive: true));
    final preferences = ProjectLaunchPreferences(
      file: File('${directory.path}/settings'),
      protect: (bytes, {decrypt = false}) => Uint8List.fromList(bytes),
    );
    await Future.wait([preferences.saveDirectory('lineage', directory.path), preferences.save('lineage/env', profile)]);
    expect(await preferences.readDirectory('lineage'), directory.path);
    expect((await preferences.read('lineage/env'))!.executable, profile.executable);
    expect(await preferences.readDirectory('unrelated'), isNull);
    expect(() => preferences.saveDirectory('lineage', 'relative'), throwsFormatException);
    await preferences.save('other/env', profile);
    await preferences.removeProject('lineage');
    expect(await preferences.readDirectory('lineage'), isNull);
    expect(await preferences.read('lineage/env'), isNull);
    expect(await preferences.read('other/env'), isNotNull);
  });
  group('launch lifecycle through a mocked native channel', () {
    const channel = MethodChannel('synthetic/project-launch');
    late VaultSession session;
    late VaultEntry entry;
    late ProjectLaunchController controller;
    final calls = <MethodCall>[];
    setUp(() async {
      session = await VaultCipher.create(password);
      final restored = await VaultCipher.unlock(await session.encrypt([environment()]), password);
      session.lock();
      session = restored;
      entry = session.entries.single;
      controller = ProjectLaunchController(channel: channel);
      calls.clear();
    });
    tearDown(() async {
      controller.dispose();
      session.lock();
      await Future<void>.delayed(Duration.zero);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    test('an approved process survives locking and remains stoppable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'prepare') return 1;
        if (call.method == 'start') return true;
        return null;
      });
      expect(await controller.start(id: 'env', session: session, entry: entry, profile: profile), isTrue);
      session.lock();
      controller.lock();
      await Future<void>.delayed(Duration.zero);
      expect(controller.running('env'), isTrue);
      expect(calls.where((call) => call.method == 'revoke' || call.method == 'stop'), isEmpty);
      await controller.stop('env');
      expect(controller.running('env'), isFalse);
      expect(calls.where((call) => call.method == 'stop'), hasLength(1));
    });

    test('locking during prepare never sends the secret payload', () async {
      final grant = Completer<int>();
      final entered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'prepare') {
          entered.complete();
          return await grant.future;
        }
        return null;
      });
      final started = controller.start(id: 'env', session: session, entry: entry, profile: profile);
      await entered.future;
      controller.lock();
      grant.complete(1);
      expect(await started, isFalse);
      expect(calls.where((call) => call.method == 'start'), isEmpty);
    });
    test('deleting one project stops its processes without stopping other projects', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'prepare') return 1;
        if (call.method == 'start') return true;
        return null;
      });
      for (final id in ['first/env', 'first/other', 'second/env']) {
        expect(await controller.start(id: id, session: session, entry: entry, profile: profile), isTrue);
      }
      await controller.stopProject('first');
      expect(controller.running('first/env'), isFalse);
      expect(controller.running('first/other'), isFalse);
      expect(controller.running('second/env'), isTrue);
      expect(calls.where((call) => call.method == 'stop'), hasLength(2));
    });
    test('an obsolete start stops only its own process, preserving a newer start', () async {
      final pending = <Completer<bool>>[];
      final entered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'prepare') return 1;
        if (call.method == 'start') {
          final response = Completer<bool>();
          pending.add(response);
          if (pending.length == 1) entered.complete();
          return await response.future;
        }
        return null;
      });
      final first = controller.start(id: 'env', session: session, entry: entry, profile: profile);
      await entered.future;
      controller.lock();
      final second = controller.start(id: 'env', session: session, entry: entry, profile: profile);
      await Future<void>.delayed(Duration.zero);
      pending[1].complete(true);
      expect(await second, isTrue);
      pending[0].complete(true);
      expect(await first, isFalse);
      expect(controller.running('env'), isTrue);
      final launches = calls.where((call) => call.method == 'start').map((call) => call.arguments as Map).toList();
      expect(launches[0]['id'], isNot(launches[1]['id']));
      expect(calls.where((call) => call.method == 'stop').single.arguments, launches[0]['id']);
      expect(launches[1]['environment']['API_TOKEN'], 'synthetic-token');
      expect(launches[1]['arguments'], ['server.js']);
    });
  });
}
