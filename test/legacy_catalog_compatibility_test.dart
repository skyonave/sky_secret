import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/legacy_projects.json').readAsStringSync()) as Map;
  final password = fixture['password'] as String;

  for (final schema in ['schema10', 'schema11']) {
    test('$schema preserves ordinary data through save and password change', () async {
      final directory = await Directory.systemTemp.createTemp('retired-catalog-synthetic-');
      addTearDown(() => directory.delete(recursive: true));
      final store = VaultStore(file: File('${directory.path}/vault.smv'));
      var session = await store.importEncryptedSnapshot(base64Decode(fixture[schema] as String), password);
      void verify() {
        expect(session.name, 'Legacy ordinary vault');
        expect(session.entries.map((entry) => entry.toJson()).toList(), fixture['entries']);
        expect(session.folders.map((folder) => folder.toJson()).toList(), fixture['folders']);
      }

      verify();
      await store.save(session, session.entries, folders: session.folders);
      session.lock();
      session = await store.unlock(password);
      verify();
      const replacement = 'Synthetic replacement passphrase 2!';
      session = await store.changePassword(session, password, replacement);
      session.lock();
      session = await store.unlock(replacement);
      verify();
      session.lock();
      await expectLater(store.unlock(password), throwsA(isA<VaultUnlockException>()));
    });
  }

  test('catalog and history ignore retired project directories', () async {
    final directory = await Directory.systemTemp.createTemp('retired-catalog-synthetic-');
    addTearDown(() => directory.delete(recursive: true));
    final catalog = VaultCatalog(directory: directory);
    final reference = catalog.newVault();
    final session = await reference.store.create(password);
    await reference.store.save(session, [VaultEntry.create(title: 'Ordinary account')]);
    session.lock();
    final retired = File('${directory.path}/projects/${reference.id}.smv');
    await retired.parent.create(recursive: true);
    await retired.writeAsString('Discarded synthetic project');
    final oldHistory = Directory('${retired.path}.history');
    await oldHistory.create();
    final ordinarySnapshot = (await reference.store.history()).single;
    await ordinarySnapshot.copy('${oldHistory.path}/${ordinarySnapshot.uri.pathSegments.last}');
    expect((await catalog.list()).map((vault) => vault.id), [reference.id]);
    expect(await catalog.history(), hasLength(1));
    for (final snapshot in await catalog.history()) {
      expect(snapshot.vault.id, reference.id);
      expect(await FileSystemEntity.identical(snapshot.vault.file.path, reference.file.path), isTrue);
    }
  });
}
