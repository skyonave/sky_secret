import 'dart:io';
import 'dart:typed_data';

import '../../../core/crypto/crypto.dart';

class VaultSessionController {
  VaultStore? _store;
  VaultCatalog? _catalog;
  VaultSession? _session;
  List<VaultReference> _vaults = [];
  final _names = <String, String>{};
  String? _selectedId;
  bool _exists = false;
  bool _disposed = false;
  int _epoch = 0;
  Object? _opening;
  VaultSession? _workspaceSession;
  VaultStore? _workspaceStore;
  String? _workspaceId;
  VaultProject? _project;

  VaultSessionController({this._store, this._catalog});

  VaultStore? get store => _store;
  VaultCatalog? get catalog => _catalog;
  VaultSession? get session => _session;
  List<VaultReference> get vaults => List.unmodifiable(_vaults);
  Map<String, String> get names => Map.unmodifiable(_names);
  String? get selectedId => _selectedId;
  bool get exists => _exists;
  VaultProject? get project => _project;
  VaultSession? get workspaceSession => _workspaceSession ?? (_project == null ? _session : null);
  List<VaultProject> get projects => workspaceSession?.projects ?? const [];
  bool get workspaceUnlocked => workspaceSession?.isLocked == false;
  bool get hasOpenSession => _session?.isLocked == false || workspaceUnlocked;
  int get epoch => _epoch;

  bool accepts(int epoch) => _disposed == false && _epoch == epoch;

  bool owns(VaultSession session) => _disposed == false && _session == session && session.isLocked == false;

  void retainWorkspace() {
    if (_project != null || _workspaceSession != null || _session == null) return;
    _workspaceSession = _session;
    _workspaceStore = _store;
    _workspaceId = _selectedId;
  }

  void leaveProject() {
    if (_project == null) return;
    _session?.lock();
    _session = _workspaceSession?.isLocked == false ? _workspaceSession : null;
    _store = _workspaceStore;
    _selectedId = _workspaceId;
    _project = null;
    _exists = true;
  }

  void suspendContext() {
    retainWorkspace();
    _opening = null;
    _epoch++;
    if (_project != null) _session?.lock();
    leaveProject();
  }

  void lockProject() {
    _opening = null;
    _epoch++;
    _session?.lock();
    _session = null;
  }

  Future<void> selectProject(VaultProject project) async {
    if (_disposed || !workspaceUnlocked) throw StateError('Workspace is locked');
    suspendContext();
    final current = projects.where((p) => p.id == project.id).firstOrNull;
    if (current == null || current.conflictOf != null) throw const VaultConflictException();
    final catalog = _catalog!;
    final target = VaultReference(
      id: current.vaultId,
      file: File('${catalog.directory.path}/projects/${current.vaultId}.smv'),
      isProject: true,
    );
    _project = current;
    _store = target.store;
    _selectedId = target.id;
    _session = null;
    _exists = true;
    if (current.unlockWithWorkspace) await open(current.credential);
  }

  Future<VaultProject?> createProject(String name, {String? password}) async {
    retainWorkspace();
    final workspace = workspaceSession;
    final store = _workspaceStore;
    final catalog = _catalog;
    if (workspace == null || workspace.isLocked || store == null || catalog == null || _disposed) return null;
    if (workspace.projects.length >= VaultCipher.maxProjects) throw const VaultFormatException();
    final epoch = _epoch;
    final target = catalog.newVault(project: true);
    final credential = password ?? PasswordGenerator().generate(length: 48);
    final created = await VaultCipher.create(credential, name: name);
    try {
      if (!accepts(epoch) || workspace.isLocked) return null;
      final project = VaultProject(
        id: target.id,
        vaultId: target.id,
        lineage: created.revision.lineage,
        name: name,
        credential: password == null ? credential : '',
      );
      await store.save(workspace, workspace.entries, projects: [...workspace.projects, project]);
      if (!accepts(epoch) || workspace.isLocked) return null;
      await target.store.saveCreated(created, allowed: () => accepts(epoch) && !workspace.isLocked);
      if (!accepts(epoch) || workspace.isLocked) return null;
      _vaults.add(target);
      return workspace.projects.firstWhere((p) => p.id == project.id);
    } finally {
      created.lock();
    }
  }

  Future<void> renameProject(String name) async {
    final project = _project;
    final workspace = workspaceSession;
    final epoch = _epoch;
    if (project == null || workspace == null || workspace.isLocked) return;
    await _workspaceStore!.save(
      workspace,
      workspace.entries,
      projects: [for (final p in workspace.projects) p.id == project.id ? p.renamed(name) : p],
    );
    if (accepts(epoch) && !workspace.isLocked && _project?.id == project.id) {
      _project = workspace.projects.firstWhere((p) => p.id == project.id);
    }
  }

  Future<void> toggleProjectArchive(VaultProject project) async {
    retainWorkspace();
    final workspace = workspaceSession;
    if (workspace == null || workspace.isLocked) return;
    final current = workspace.projects.where((p) => p.id == project.id).firstOrNull;
    if (current == null) return;
    await _workspaceStore!.save(
      workspace,
      workspace.entries,
      projects: [for (final p in workspace.projects) p.id == current.id ? p.withArchived(!p.archived) : p],
    );
  }

  Future<void> deleteProject(VaultProject project) async {
    retainWorkspace();
    final workspace = workspaceSession;
    final store = _workspaceStore;
    final catalog = _catalog;
    if (_disposed || workspace == null || workspace.isLocked || store == null || catalog == null) return;
    final current = workspace.projects.where((p) => p.id == project.id).firstOrNull;
    if (current == null) return;
    if (_project?.vaultId == current.vaultId) suspendContext();
    final epoch = _epoch;
    bool valid() => accepts(epoch) && !workspace.isLocked;
    final remaining = workspace.projects.where((p) => p.id != current.id).toList();
    if (remaining.every((p) => p.vaultId != current.vaultId)) {
      final directory = Directory('${catalog.directory.path}/projects');
      final type = await FileSystemEntity.type(directory.path, followLinks: false);
      if (!valid()) return;
      if (type == FileSystemEntityType.directory) {
        final target = VaultStore(file: File('${directory.path}/${current.vaultId}.smv'));
        await target.delete(allowed: valid, retainSnapshots: false, allowMissing: true);
      } else if (type != FileSystemEntityType.notFound) {
        throw const FileSystemException('Project directory is not a regular directory');
      }
    }
    if (!valid()) return;
    await store.save(workspace, workspace.entries, projects: remaining);
    if (valid()) _vaults.removeWhere((v) => v.id == current.vaultId && remaining.every((p) => p.vaultId != v.id));
  }

  Future<VaultProject?> resolveProject(VaultProject project) async {
    retainWorkspace();
    final workspace = workspaceSession;
    if (workspace == null || workspace.isLocked) return null;
    final current = workspace.projects.where((p) => p.id == project.id).firstOrNull;
    if (current == null || current.conflictOf == null) return current;
    await _workspaceStore!.save(
      workspace,
      workspace.entries,
      projects: [
        for (final p in workspace.projects)
          if (p.id == current.id) p.resolved() else if (p.conflictOf == current.conflictOf) p.withArchived(true) else p,
      ],
    );
    if (workspace.isLocked) return null;
    return workspace.projects.firstWhere((p) => p.id == current.id);
  }

  Future<bool> restoreProject(File file, {String? password}) async {
    final epoch = _epoch;
    final bytes = await VaultStore(file: file).readEncryptedSnapshot();
    if (!accepts(epoch)) return false;
    return restoreProjectBytes(bytes, password: password);
  }

  Future<bool> restoreProjectBytes(Uint8List bytes, {String? password}) async {
    final project = _project;
    final store = _store;
    final workspace = workspaceSession;
    final epoch = _epoch;
    if (project == null || store == null || workspace == null || workspace.isLocked) return false;
    var opened = await VaultCipher.unlock(bytes, password ?? (project.unlockWithWorkspace ? project.credential : ''));
    try {
      if (!accepts(epoch) || workspace.isLocked) return false;
      if (opened.revision.lineage != project.lineage) throw const VaultUnlockException();
      if (project.unlockWithWorkspace && password != null) {
        final replacement = await opened.changePassword(project.credential);
        opened.lock();
        opened = replacement;
      }
      await store.saveCreated(opened, allowed: () => accepts(epoch) && !workspace.isLocked);
    } finally {
      opened.lock();
    }
    return accepts(epoch) && await open(project.unlockWithWorkspace ? project.credential : password ?? '');
  }

  Future<void> load() async {
    final epoch = _epoch;
    if (_store == null) {
      final catalog = _catalog ?? VaultCatalog.local();
      final vaults = await catalog.list(includeProjects: false);
      if (accepts(epoch) == false) return;
      if (vaults.isEmpty) vaults.add(catalog.legacy);
      _catalog = catalog;
      _vaults = vaults;
      _selectedId = vaults.first.id;
      _store = vaults.first.store;
    }
    final exists = await _store!.exists();
    if (accepts(epoch)) _exists = exists;
  }

  Future<void> select(String? id) async {
    final catalog = _catalog;
    if (catalog == null) return;
    lock();
    final epoch = _epoch;
    final vaults = await catalog.list(includeProjects: false);
    if (accepts(epoch) == false) return;
    final selected = id == null
        ? (vaults.isEmpty ? catalog.legacy : catalog.newVault())
        : vaults.where((vault) => vault.id == id).firstOrNull;
    if (selected == null) throw StateError('Selected vault is unavailable');
    if (id == null) vaults.add(selected);
    _vaults = vaults;
    _store = selected.store;
    _selectedId = selected.id;
    await load();
  }

  Future<bool> open(String password, {String? name}) async {
    final epoch = _epoch;
    final store = _store;
    if (store == null || _disposed) return false;
    final request = Object();
    _opening = request;
    final VaultSession opened;
    try {
      opened = _exists ? await store.unlock(password) : await store.create(password, name: name);
    } on VaultConflictException {
      if (accepts(epoch)) await load();
      rethrow;
    }
    if (accepts(epoch) == false || _opening != request) {
      opened.lock();
      return false;
    }
    if (_project != null && opened.revision.lineage != _project!.lineage) {
      opened.lock();
      throw const VaultUnlockException();
    }
    _replace(opened);
    return true;
  }

  Future<bool> importFile(File file, String password) async {
    final catalog = _catalog;
    if (catalog == null || _disposed) return false;
    final epoch = _epoch;
    final target = catalog.newVault();
    final imported = await target.store.importFrom(file, password, allowed: () => accepts(epoch));
    return _acceptImport(target, imported, epoch);
  }

  Future<bool> importBytes(
    VaultReference target,
    Uint8List bytes,
    String password,
  ) async {
    final epoch = _epoch;
    if (_disposed) return false;
    final imported = await target.store.importEncryptedSnapshot(bytes, password, allowed: () => accepts(epoch));
    return _acceptImport(target, imported, epoch);
  }

  bool _acceptImport(
    VaultReference target,
    VaultSession imported,
    int epoch,
  ) {
    if (accepts(epoch) == false) {
      imported.lock();
      return false;
    }
    _workspaceSession?.lock();
    _workspaceSession = null;
    _workspaceStore = null;
    _workspaceId = null;
    _project = null;
    _store = target.store;
    _selectedId = target.id;
    _vaults.add(target);
    _replace(imported);
    return true;
  }

  Future<bool> changePassword(String current, String replacement) async {
    final session = _session;
    final store = _store;
    final epoch = _epoch;
    if (session == null || store == null || owns(session) == false) return false;
    final changed = await store.changePassword(session, current, replacement);
    if (accepts(epoch) == false) {
      changed.lock();
      return false;
    }
    _replace(changed);
    return true;
  }

  Future<bool> save(
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    final session = _session;
    final store = _store;
    if (session == null || store == null || owns(session) == false) return false;
    await store.save(session, entries, folders: folders, name: name);
    if (owns(session) == false) return false;
    rememberName();
    return true;
  }

  void rememberName() {
    final name = _session?.name;
    final id = _selectedId;
    if (name != null && id != null) _names[id] = name;
  }

  Future<void> deleteSelected() async {
    final store = _store;
    final id = _selectedId;
    if (store == null || _disposed) return;
    final epoch = _epoch;
    _opening = null;
    _session?.lock();
    _session = null;
    _workspaceSession?.lock();
    _workspaceSession = null;
    _workspaceStore = null;
    _workspaceId = null;
    _project = null;
    await store.delete(allowed: () => accepts(epoch) && _store == store);
    if (accepts(epoch) == false) return;
    _names.remove(id);
    _store = null;
    _selectedId = null;
    _exists = false;
    await load();
  }

  void _replace(VaultSession session) {
    _opening = null;
    if (_session == session) return;
    if (_session != _workspaceSession || _project == null) _session?.lock();
    _session = session;
    if (_project == null && _workspaceSession != null) _workspaceSession = session;
    _exists = true;
    rememberName();
  }

  void lock() {
    _opening = null;
    _epoch++;
    _session?.lock();
    _session = null;
    _workspaceSession?.lock();
    leaveProject();
    _workspaceSession = null;
    _workspaceStore = null;
    _workspaceId = null;
  }

  void dispose() {
    lock();
    _names.clear();
    _disposed = true;
  }
}
