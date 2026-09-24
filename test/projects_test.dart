import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/ui/vault/controllers/vault_session_controller.dart';
import 'package:skysecret/ui/vault/controllers/vault_browser_controller.dart';
import 'package:skysecret/ui/vault/controllers/vault_sync_controller.dart';
import 'package:skysecret/core/sync/github/controllers/github_backup.dart';

import 'vault_sections_test.dart' show fixture;
import 'github_test.dart' show MemoryStorage, seed;
import 'vault_sync_test.dart' show RacingGitHub;

const _master = 'Synthetic workspace phrase 429!';
const _separate = 'Synthetic separate phrase 783!';
const _replacement = 'Synthetic replacement phrase 512!';

class _DelayedProjectReference extends VaultReference {
  final VaultStore delayed;
  _DelayedProjectReference(VaultReference source, this.delayed)
    : super(id: source.id, file: source.file, isProject: true);
  @override
  VaultStore get store => delayed;
}

class _DelayedProjectCatalog extends VaultCatalog {
  final entered = Completer<void>();
  final release = Completer<void>();
  _DelayedProjectCatalog(Directory directory) : super(directory: directory);
  @override
  VaultReference newVault({bool project = false}) {
    final reference = super.newVault(project: project);
    if (!project) return reference;
    return _DelayedProjectReference(
      reference,
      VaultStore(
        file: reference.file,
        beforeCommit: () async {
          entered.complete();
          await release.future;
        },
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late VaultCatalog catalog;
  late VaultSessionController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('skysecret-project-unit-');
    catalog = VaultCatalog(directory: directory);
    controller = VaultSessionController(catalog: catalog);
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  Future<VaultProject> create({bool separate = false}) async {
    if (controller.session == null) await controller.open(_master, name: 'Synthetic general');
    return (await controller.createProject('Synthetic project', password: separate ? _separate : null))!;
  }

  test('a completed rename cannot restore a project after leaving its context', () async {
    final project = await create();
    final rootFile = controller.store!.file;
    controller.dispose();
    final entered = Completer<void>();
    final release = Completer<void>();
    controller = VaultSessionController(
      catalog: catalog,
      store: VaultStore(
        file: rootFile,
        beforeCommit: () async {
          entered.complete();
          await release.future;
        },
      ),
    );
    await controller.load();
    await controller.open(_master);
    await controller.selectProject(controller.projects.single);
    final renaming = controller.renameProject('Renamed');
    await entered.future;
    controller.suspendContext();
    release.complete();
    await renaming;
    expect(controller.project, isNull);
    expect(controller.session, same(controller.workspaceSession));
    expect(controller.projects.single.id, project.id);
    expect(controller.projects.single.name, 'Renamed');
  });

  test('shared projects have independent keys and never appear among general secrets or search', () async {
    await controller.open(_master);
    await controller.save([VaultEntry.create(title: 'Synthetic everyday', password: 'Synthetic value')]);
    final root = controller.session!;
    final project = await create();
    expect(project.unlockWithWorkspace, isTrue);
    expect(root.entries.single.title, 'Synthetic everyday');
    expect(VaultBrowserController().suggestions(root, 'Synthetic project'), isEmpty);
    await controller.selectProject(project);
    final opened = controller.session!;
    expect(opened.hasSameKeyEnvelope(root), isFalse);
    expect(opened.entries, isEmpty);
    await controller.save([VaultEntry.create(title: 'Synthetic project entry')]);
    controller.suspendContext();
    expect(opened.isLocked, isTrue);
    expect(identical(controller.session, root), isTrue);
    expect(root.entries.single.title, 'Synthetic everyday');
    final files = await catalog.list();
    expect(files.where((v) => v.isProject).single.id, project.vaultId);
    expect(files.where((v) => !v.isProject).single.id, 'legacy');
  });

  test('separate project stores no credential and rejects workspace and incorrect passwords', () async {
    final project = await create(separate: true);
    expect(project.credential, isEmpty);
    await controller.selectProject(project);
    expect(controller.session, isNull);
    await expectLater(controller.open(_master), throwsA(isA<VaultUnlockException>()));
    expect(await controller.open(_separate), isTrue);
    controller.lockProject();
    expect(controller.workspaceUnlocked, isTrue);
    expect(controller.session, isNull);
    expect(await controller.open(_separate), isTrue);
  });

  test('project deletion removes its file and snapshots, preserves general and source files', () async {
    final project = await create();
    final second = (await controller.createProject('Other project'))!;
    await controller.selectProject(project);
    await controller.save([VaultEntry.create(title: 'Synthetic entry')]);
    final child = controller.session!;
    final childStore = controller.store!;
    expect(await childStore.history(), isNotEmpty);
    final source = File('${directory.path}/source/.env');
    await source.parent.create();
    await source.writeAsString('SYNTHETIC=value');
    await controller.deleteProject(project);
    expect(child.isLocked, isTrue);
    expect(await childStore.exists(), isFalse);
    expect(await childStore.history(), isEmpty);
    expect(await source.readAsString(), 'SYNTHETIC=value');
    expect(controller.projects.single.id, second.id);
    controller.lock();
    await controller.open(_master);
    expect(controller.projects.single.id, second.id);
    await controller.selectProject(controller.projects.single);
    expect(controller.session!.isLocked, isFalse);
  });

  test('missing or archived project can be deleted and cannot be resurrected by late save', () async {
    final project = await create(separate: true);
    await controller.toggleProjectArchive(project);
    await controller.selectProject(controller.projects.single);
    await controller.open(_separate);
    final child = controller.session!;
    final store = controller.store!;
    controller.suspendContext();
    await store.file.delete();
    await controller.deleteProject(controller.projects.single);
    expect(controller.projects, isEmpty);
    await expectLater(store.save(child, []), throwsStateError);
    expect(await store.exists(), isFalse);
  });

  test('deleting a duplicate catalog reference preserves the shared project file', () async {
    final project = await create();
    final duplicate = VaultProject(
      id: 'duplicate',
      vaultId: project.vaultId,
      lineage: project.lineage,
      name: 'Duplicate',
      credential: project.credential,
      archived: true,
    );
    await controller.store!.save(controller.session!, [], projects: [project, duplicate]);
    await controller.deleteProject(project);
    expect(controller.projects.single.id, 'duplicate');
    await controller.selectProject(controller.projects.single);
    expect(controller.session!.isLocked, isFalse);
  });

  test('catalog write failure leaves a retryable reference after project file removal', () async {
    final project = await create();
    final rootFile = controller.store!.file;
    controller.dispose();
    var fail = false;
    controller = VaultSessionController(
      catalog: catalog,
      store: VaultStore(
        file: rootFile,
        beforeCommit: () async {
          if (fail) throw const FileSystemException('Synthetic');
        },
      ),
    );
    await controller.load();
    await controller.open(_master);
    fail = true;
    await expectLater(controller.deleteProject(controller.projects.single), throwsA(isA<FileSystemException>()));
    expect(controller.projects.single.id, project.id);
    fail = false;
    await controller.deleteProject(controller.projects.single);
    expect(controller.projects, isEmpty);
  });

  test('workspace lock revokes project credentials and both sessions', () async {
    final project = await create();
    final root = controller.session!;
    await controller.selectProject(project);
    final child = controller.session!;
    controller.lock();
    expect(root.isLocked, isTrue);
    expect(child.isLocked, isTrue);
    expect(controller.workspaceUnlocked, isFalse);
    expect(() => project.credential, throwsStateError);
    await expectLater(controller.selectProject(project), throwsStateError);
    expect(await controller.open(_master), isTrue);
    await controller.selectProject(controller.projects.single);
    expect(controller.session!.isLocked, isFalse);
  });

  test('ordinary save and workspace password rotation preserve project grants', () async {
    final project = await create();
    final credential = project.credential;
    await controller.save([VaultEntry.authenticator(title: 'Synthetic TOTP', totp: 'JBSWY3DPEHPK3PXP')]);
    expect(await controller.changePassword(_master, _replacement), isTrue);
    controller.lock();
    await expectLater(controller.open(_master), throwsA(isA<VaultUnlockException>()));
    expect(await controller.open(_replacement), isTrue);
    expect(controller.session!.entries.single.hasTotp, isTrue);
    expect(controller.projects.single.credential, credential);
    await controller.selectProject(controller.projects.single);
    expect(controller.session!.isLocked, isFalse);
  });

  test('a missing project never becomes an empty replacement', () async {
    final project = await create();
    final target = (await catalog.list()).singleWhere((v) => v.isProject).file;
    await target.delete();
    await expectLater(controller.selectProject(project), throwsA(isA<FileSystemException>()));
    expect(await target.exists(), isFalse);
    await expectLater(controller.open(project.credential), throwsA(isA<FileSystemException>()));
    expect(await target.exists(), isFalse);
    expect(controller.workspaceUnlocked, isTrue);
  });

  test('matching password is insufficient when a project file has another lineage', () async {
    final project = await create();
    final target = (await catalog.list()).singleWhere((v) => v.isProject).file;
    final other = await VaultCipher.create(project.credential);
    addTearDown(other.lock);
    await target.writeAsBytes(other.persistedBytes);
    await expectLater(controller.selectProject(project), throwsA(isA<VaultUnlockException>()));
    expect(controller.session, isNull);
    expect(controller.workspaceUnlocked, isTrue);
  });

  test('shared export has an independent password and restores without replacing an existing file', () async {
    final project = await create();
    await controller.selectProject(project);
    await controller.save([VaultEntry.create(title: 'Synthetic recovery payload', notes: 'Synthetic notes')]);
    final exported = await controller.session!.exportWithPassword(_separate);
    final backup = File('${directory.path}/synthetic-export.smv');
    await controller.store!.exportTo(exported, backup);
    exported.lock();
    final target = controller.store!.file;
    final original = await target.readAsBytes();
    await expectLater(controller.restoreProject(backup, password: _separate), throwsA(isA<VaultConflictException>()));
    expect(await target.readAsBytes(), original);
    controller.lockProject();
    await target.delete();
    expect(await controller.restoreProject(backup, password: _separate), isTrue);
    expect(controller.session!.entries.single.notes, 'Synthetic notes');
    controller.lock();
    await controller.open(_master);
    await controller.selectProject(controller.projects.single);
    expect(controller.session!.entries.single.title, 'Synthetic recovery payload');
  });

  test('archiving preserves credentials, project bytes and unrelated secrets', () async {
    final project = await create();
    final credential = project.credential;
    final target = (await catalog.list()).singleWhere((v) => v.isProject).file;
    final bytes = await target.readAsBytes();
    controller.lock();
    await controller.open(_master);
    await controller.toggleProjectArchive(controller.projects.single);
    expect(controller.projects.single.archived, isTrue);
    expect(controller.projects.single.credential, credential);
    expect(await target.readAsBytes(), bytes);
    await controller.toggleProjectArchive(controller.projects.single);
    expect(controller.projects.single.archived, isFalse);
  });

  test('downloaded project snapshot restores with its workspace grant and rejects another lineage', () async {
    final project = await create();
    await controller.selectProject(project);
    await controller.save([VaultEntry.create(title: 'Synthetic downloaded contents')]);
    final bytes = controller.session!.persistedBytes;
    final target = controller.store!.file;
    controller.lockProject();
    await target.delete();
    final unrelated = await VaultCipher.create(project.credential);
    try {
      await expectLater(controller.restoreProjectBytes(unrelated.persistedBytes), throwsA(isA<VaultUnlockException>()));
      expect(await target.exists(), isFalse);
    } finally {
      unrelated.lock();
    }
    expect(await controller.restoreProjectBytes(bytes), isTrue);
    expect(controller.session!.entries.single.title, 'Synthetic downloaded contents');
    await expectLater(controller.restoreProjectBytes(bytes), throwsA(isA<VaultConflictException>()));
    expect(await target.readAsBytes(), bytes);
  });

  test('GitHub restoration retains project identity, shared unlock and synchronization binding', () async {
    final project = await create();
    await controller.selectProject(project);
    await controller.save([VaultEntry.create(title: 'Synthetic remote project')]);
    final api = RacingGitHub();
    final backup = GitHubBackup(catalog: catalog, storage: MemoryStorage(seed()), api: api);
    addTearDown(backup.dispose);
    await backup.initialize(schedule: false);
    final sync = VaultSyncController(controller);
    expect(await sync.synchronize(backup), VaultSyncResult.done);
    final remote = api.remote.values.single;
    final bytes = api.blobs[remote.blob]!;
    await expectLater(
      sync.restore(backup, bytes, '', remote: remote, intoProject: true),
      throwsA(isA<VaultConflictException>()),
    );
    final target = controller.store!.file;
    controller.lockProject();
    await target.delete();
    expect(await sync.restore(backup, bytes, '', remote: remote, intoProject: true), isTrue);
    expect(controller.project!.id, project.id);
    expect(controller.selectedId, project.vaultId);
    expect(backup.localForRemote(remote.id), project.vaultId);
    expect(controller.session!.entries.single.title, 'Synthetic remote project');
    expect(controller.workspaceSession!.entries, isEmpty);
    expect(await sync.synchronize(backup), VaultSyncResult.done);
  });

  test(
    'project creation failure retains an encrypted access record and never creates a plaintext credential',
    () async {
      await controller.open(_master);
      await File('${directory.path}/projects').writeAsString('synthetic obstruction');
      await expectLater(controller.createProject('Synthetic pending project'), throwsA(isA<FileSystemException>()));
      expect(controller.projects.single.name, 'Synthetic pending project');
      final bytes = await catalog.legacy.file.readAsBytes();
      expect(String.fromCharCodes(bytes), isNot(contains(controller.projects.single.credential)));
      expect(controller.session!.entries, isEmpty);
    },
  );

  test('project catalog merges concurrent additions and retains conflicting versions', () async {
    final project = await create();
    final root = controller.session!;
    final base = await root.openRevision(root.persistedBytes);
    final localBytes = await root.encrypt(root.entries, projects: [project.renamed('Synthetic left')]);
    final local = await root.openRevision(localBytes);
    final remoteBytes = await root.encrypt(root.entries, projects: [project.renamed('Synthetic right')]);
    final remote = await root.openRevision(remoteBytes);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(merged.projects, hasLength(2));
    expect(merged.conflicts, 1);
    expect(merged.projects.every((p) => p.credential == project.credential), isTrue);
    expect(merged.projects.every((p) => p.conflictOf == project.id), isTrue);
    final encoded = await root.encrypt(merged.entries, projects: merged.projects);
    final read = await root.openRevision(encoded);
    expect(read.projects, hasLength(2));
    expect(await VaultMerge.sameContents(merged, read), isTrue);
  });

  test('schema 8 preserves all old fields when upgraded to project schema and reopened', () async {
    final revision = VaultRevision(VaultRevision.randomId(), {});
    final entry = VaultEntry.create(
      title: 'Synthetic old entry',
      username: 'Synthetic username',
      password: 'Synthetic password',
      notes: 'Synthetic notes',
    ).withFavorite(true).inTrash(123);
    final old = await fixture({
      'schemaVersion': 8,
      'revision': revision.toJson(),
      'name': 'Synthetic old',
      'folders': <Object>[],
      'entries': [entry.toJson()],
    });
    await catalog.legacy.file.writeAsBytes(old);
    await controller.load();
    await controller.open('synthetic legacy password');
    final before = controller.session!.entries.single.toJson();
    await controller.createProject('Synthetic new project');
    controller.lock();
    await controller.open('synthetic legacy password');
    expect(controller.session!.entries.single.toJson(), before);
    expect(controller.projects, hasLength(1));
  });

  test('project metadata rejects path traversal, malformed grants and unknown fields', () {
    final valid = VaultProject(id: 'synthetic', vaultId: 'a' * 32, lineage: 'b' * 32, name: 'Synthetic').toJson();
    for (final change in [
      {'vaultId': '../vault'},
      {'lineage': 'invalid'},
      {'credential': 'weak'},
      {'name': ''},
      {'archived': 'false'},
      {'unknown': true},
    ]) {
      expect(() => VaultProject.fromJson({...valid, ...change}), throwsA(isA<VaultFormatException>()));
    }
  });

  test('workspace lock cancels a project commit already waiting on disk', () async {
    final delayed = _DelayedProjectCatalog(directory);
    controller.dispose();
    controller = VaultSessionController(catalog: delayed);
    await controller.load();
    await controller.open(_master);
    final creating = controller.createProject('Synthetic cancelled');
    final checked = expectLater(creating, throwsStateError);
    await delayed.entered.future;
    controller.lock();
    delayed.release.complete();
    await checked;
    expect((await catalog.list()).where((v) => v.isProject), isEmpty);
    await controller.open(_master);
    expect(controller.projects.single.name, 'Synthetic cancelled');
  });

  test('locking the source immediately revokes a prepared independent export', () async {
    await create();
    final source = controller.session!;
    final exported = await source.exportWithPassword(_separate);
    final grant = exported.projects.single;
    source.lock();
    expect(exported.isLocked, isTrue);
    expect(() => grant.credential, throwsStateError);
  });

  test('damaged project directory does not block access to the general vault', () async {
    await controller.open(_master);
    await controller.save([VaultEntry.create(title: 'Synthetic general remains')]);
    controller.dispose();
    await File('${directory.path}/projects').writeAsString('Synthetic obstruction');
    controller = VaultSessionController(catalog: catalog);
    await controller.load();
    await controller.open(_master);
    expect(controller.session!.entries.single.title, 'Synthetic general remains');
    await expectLater(catalog.list(), throwsA(isA<FileSystemException>()));
  });

  test('importing another general vault never saves its projects into the previous workspace', () async {
    await create();
    final source = File('${directory.path}/synthetic-import.smv');
    final imported = await VaultStore(file: source).create(_separate);
    imported.lock();
    await controller.importFile(source, _separate);
    await controller.createProject('Synthetic imported workspace project');
    final original = await catalog.legacy.store.unlock(_master);
    addTearDown(original.lock);
    expect(original.projects.single.name, 'Synthetic project');
    expect(controller.projects.single.name, 'Synthetic imported workspace project');
  });

  test('deleting a general vault clears retained workspace before creating another', () async {
    final project = await create();
    final projectFile = File('${directory.path}/projects/${project.vaultId}.smv');
    final originalBytes = await projectFile.readAsBytes();
    await controller.deleteSelected();
    expect(controller.workspaceSession, isNull);
    expect(controller.projects, isEmpty);
    await controller.open(_replacement);
    await controller.createProject('Synthetic next workspace');
    expect(controller.projects.single.name, 'Synthetic next workspace');
    expect(await projectFile.readAsBytes(), originalBytes);
  });

  test('merge grants are revoked with their workspace and conflict resolution retains alternatives', () async {
    final project = await create();
    final root = controller.session!;
    final base = await root.openRevision(root.persistedBytes);
    final left = await root.openRevision(await root.encrypt(root.entries, projects: [project.renamed('Synthetic L')]));
    final right = await root.openRevision(await root.encrypt(root.entries, projects: [project.renamed('Synthetic R')]));
    final merged = await VaultMerge.combine(base, left, right);
    final held = merged.projects.first;
    await controller.store!.save(root, root.entries, projects: merged.projects);
    controller.lock();
    await controller.open(_master);
    final resolved = await controller.resolveProject(controller.projects.first);
    expect(resolved!.conflictOf, isNull);
    expect(controller.projects.where((p) => p.archived), hasLength(1));
    expect(controller.projects.where((p) => !p.archived), hasLength(1));
    controller.lock();
    expect(() => held.credential, throwsStateError);
  });
}
