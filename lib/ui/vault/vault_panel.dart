import '../shared/desktop_tooltip.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/crypto/crypto.dart';
import '../../core/desktop/editor/controllers/file_viewer_manager.dart';
import '../../core/desktop/totp/controllers/totp_window_manager.dart';
import '../../core/desktop/totp/controllers/totp_session.dart';
import '../../core/desktop/drag/controllers/file_drag_controller.dart';
import '../../core/desktop/drag/controllers/secret_drag_controller.dart';
import '../../core/os/windows/services/ssh_connections.dart';
import '../../core/settings/repositories/vault_preferences.dart';
import '../../core/settings/repositories/vault_tree_preferences.dart';
import '../../core/settings/repositories/shortcut_settings.dart';

import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/os/windows/window/window_privacy.dart';
import '../../core/os/windows/window/desktop_startup.dart';
import '../../core/files/text/models/text_document.dart';
import '../../core/files/services/vault_file_import.dart';
import '../../core/files/text/services/vault_text_file.dart';
import '../../core/sync/github/controllers/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../github/github_dialog.dart';
import '../github/controllers/github_settings_controller.dart';
import '../../core/desktop/search/controllers/vault_search_presenter.dart';
import '../shared/menu/inset_menu_item.dart';
import '../shared/desktop_option.dart';
import '../shared/notifications/desktop_notice.dart';
import '../shared/menu/desktop_menu.dart';
import '../shared/menu/desktop_select.dart';
import '../shared/files/save_file_dialog.dart';
import '../shared/input/sensitive_text_editing.dart';
import '../generator/generator_dialog.dart';
import '../generator/services/generator_service.dart';
import '../generator/services/configuration_generator_preferences.dart';
import '../../core/settings/repositories/generator_preferences.dart';

import 'dialogs/vault_name_dialog.dart';
import 'dialogs/vault_password_dialog.dart';
import 'controllers/vault_entry_controller.dart';
import 'controllers/vault_session_controller.dart';
import 'controllers/vault_sync_controller.dart';
import 'controllers/vault_browser_controller.dart';
import 'controllers/vault_deletion_controller.dart';
import '../../core/desktop/configuration/controllers/configuration_windows.dart';
import '../../core/projects/controllers/project_launch_controller.dart';
import '../../core/projects/services/project_dotenv.dart';
import '../../core/projects/services/project_env_import.dart';
import '../../core/crypto/generator/models/generator_options.dart';
import '../../core/projects/models/project_launch_profile.dart';
import '../../core/projects/repositories/project_launch_preferences.dart';
import '../shared/configuration/configuration_page.dart';
import '../shared/app_theme.dart';
import '../settings/configuration_shortcuts.dart';
import '../settings/shortcut_dialog.dart';
import 'controllers/vault_tree_state_controller.dart';

part 'widgets/_vault_tree.dart';
part 'controllers/_vault_tree_controller.dart';
part 'widgets/_vault_browser.dart';
part 'widgets/_vault_create_actions.dart';
part 'widgets/_vault_field.dart';
part 'widgets/_vault_entry_editor.dart';
part 'widgets/_vault_header.dart';
part 'widgets/_vault_unlock_form.dart';
part 'widgets/_projects_panel.dart';
part 'dialogs/_project_create_dialog.dart';
part 'dialogs/_vault_configuration_forms.dart';
part 'dialogs/_project_environment_dialog.dart';
part 'dialogs/_project_import_dialog.dart';
part 'dialogs/_project_launch_dialog.dart';
part 'dialogs/_entry_configuration_dialog.dart';
part 'dialogs/_configuration_choice_dialog.dart';
part 'widgets/_project_workspace.dart';
part 'widgets/_project_secrets_panel.dart';
part 'dialogs/_vault_preferences_dialog.dart';
part 'widgets/_vault_entry_card.dart';
part 'dialogs/_vault_text_file_dialog.dart';
part 'widgets/_vault_folder_selector.dart';
part 'widgets/_vault_switcher.dart';
part 'widgets/_vault_folder_tree.dart';
part 'widgets/_vault_entry_item.dart';
part 'controllers/_vault_entry_presenter.dart';
part 'widgets/_vault_workspace.dart';
part 'widgets/_vault_drop_target.dart';
part 'widgets/_vault_draggable.dart';
part 'widgets/_vault_entry_target.dart';
part 'widgets/_vault_tree_children.dart';
part 'widgets/_vault_folder_node.dart';
part 'models/_vault_drag.dart';

class VaultPanel extends StatefulWidget {
  final GeneratorService? generatorService;
  final bool active;
  final ValueChanged<bool>? onSectionChanged;
  final ValueChanged<bool>? onWorkspaceChanged;
  final VaultStore? store;
  final VaultCatalog? catalog;
  final VaultPreferences? preferences;
  final GitHubBackup? githubBackup;
  final ValueChanged<bool>? onSshAuthorizationChanged;
  final ValueChanged<bool>? onFileDragChanged;
  final Future<bool> Function(String) copySecret;
  final Future<void> Function() clearClipboard;
  final Future<void> Function()? onSearchDismissed;
  final VoidCallback? onCodesBlur;
  final ValueChanged<VoidCallback?>? onSearchHandlerChanged;
  final HotKey Function()? searchShortcut;

  const VaultPanel({
    super.key,
    this.active = true,
    this.onSectionChanged,
    this.onWorkspaceChanged,
    this.generatorService,
    this.store,
    this.catalog,
    this.preferences,
    this.githubBackup,
    this.onSshAuthorizationChanged,
    this.onFileDragChanged,
    required this.copySecret,
    required this.clearClipboard,
    this.onSearchDismissed,
    this.onCodesBlur,
    this.onSearchHandlerChanged,
    this.searchShortcut,
  });

  @override
  State<VaultPanel> createState() => VaultPanelState();
}

class VaultPanelState extends State<VaultPanel> {
  late final _generatorService = widget.generatorService ?? GeneratorService(GeneratorPreferences());

  int _generatorEpoch = 0;
  int _generationRequest = 0;

  bool get _hasPasswordEditor => _editor.active && !_editor.isTotp;

  void _cancelPasswordGeneration() {
    _generatorEpoch++;
    _generationRequest++;
  }

  void _useGeneratedPassword(String value, {required int epoch}) {
    if (!mounted ||
        epoch != _generatorEpoch ||
        _busy ||
        !_hasPasswordEditor ||
        _session == null ||
        _session!.isLocked) {
      return;
    }
    _generationRequest++;
    setState(() {
      _editor.applyGeneratedPassword(value);
      _error = null;
    });
    _touchActivity();
  }

  late final VaultSessionController _lifecycle;
  late final VaultSyncController _sync;
  bool _loading = true;
  bool _projectsMode = false;
  bool _archivedProjects = false;
  String? _openingProjectId;
  VaultSession? _resourcesSession;
  String? _projectDirectory;
  bool _entryWindowOpen = false;
  bool _windowShown = false;
  bool _restoreCodesPending = false;
  bool get _inlineEditorActive => _editor.active && !_entryWindowOpen;
  String? _environmentId;
  final _projectLaunch = ProjectLaunchController();
  late final _launchPreferences = ProjectLaunchPreferences.local();
  final _launchProfiles = <String, ProjectLaunchProfile>{};
  bool get _showingProjects => _projectsMode && _lifecycle.project == null && _lifecycle.workspaceUnlocked;
  bool get _contentActive => widget.active && !_showingProjects && !ConfigurationWindows.opened.value;
  bool _busy = false;
  bool _busyProgress = true;
  bool _waitingForPassword = false;
  String? _error;
  final _treeState = VaultTreeStateController();
  Set<String> get _collapsedFolders => _treeState.collapsed;
  final _vaultName = TextEditingController();
  final _renameName = TextEditingController();
  bool _renamingVault = false;
  bool _renameInvalid = false;
  final _treeKey = GlobalKey<_VaultTreeState>();
  final _browserScroll = ScrollController();
  final _formScroll = ScrollController(keepScrollOffset: false);
  final _editor = VaultEntryController();
  final _browser = VaultBrowserController();
  final _searchWindow = VaultSearchPresenter();
  bool _searching = false;
  final _deletions = VaultDeletionController();
  final _deletedEntries = <String, VaultEntry>{};
  Timer? _deletionTimer;
  Timer? _idleTimer;
  Timer? _copyNoticeTimer;
  ({VaultSession session, String entryId})? _copyNotice;
  VaultPreferences? _preferences;
  VaultTreePreferences? _treePreferences;
  bool _autoLockEnabled = true;
  bool _lockWhenHidden = true;
  bool _savingPreferences = false;
  final _master = TextEditingController();
  final _confirmation = TextEditingController();
  late final SshConnections _sshConnections;
  final _viewers = FileViewerManager();
  final _codesWindow = TotpWindowManager();
  late final _fileDrag = FileDragController(onActiveChanged: (active) => widget.onFileDragChanged?.call(active));
  late final _secretDrag = SecretDragController(onActiveChanged: (active) => widget.onFileDragChanged?.call(active));
  ({int pointer, Offset origin, VaultEntry entry})? _externalDragCandidate;
  static const _systemLock = MethodChannel('skysecret/system_lock');
  bool _sensitiveDialogOpen = false;

  VaultStore? get _store => _lifecycle.store;
  VaultCatalog? get _catalog => _lifecycle.catalog;
  List<VaultReference> get _vaults => _lifecycle.vaults;
  String? get _selectedVaultId => _lifecycle.selectedId;
  Map<String, String> get _knownVaultNames => _lifecycle.names;
  VaultSession? get _session => _lifecycle.session;
  bool get _exists => _lifecycle.exists;
  int get _securityEpoch => _lifecycle.epoch;

  Future<dynamic> _configuration(
    String kind, {
    Map<String, dynamic> data = const {},
    Future<dynamic> Function(String, dynamic)? onAction,
  }) async {
    final epoch = _securityEpoch;
    try {
      final result = await ConfigurationWindows.open(
        kind: kind,
        locale: LocaleSettings.currentLocale.languageCode,
        data: data,
        isValid: () => mounted && epoch == _securityEpoch,
        onAction: onAction,
      );
      return mounted && epoch == _securityEpoch ? result : null;
    } catch (_) {
      if (mounted) _notice(t.configurationFailed);
      return null;
    }
  }

  Future<void> _openProjectSecrets() async {
    final session = _session;
    if (!_windowShown ||
        _lifecycle.project == null ||
        session == null ||
        session.isLocked ||
        identical(_resourcesSession, session)) {
      return;
    }
    _resourcesSession = session;
    bool valid() => mounted && _windowShown && identical(_session, session) && !session.isLocked;
    try {
      await ConfigurationWindows.open(
        kind: 'projectSecrets',
        companion: true,
        locale: LocaleSettings.currentLocale.languageCode,
        data: {'title': _heading},
        isValid: valid,
        onAction: (method, arguments) async {
          if (!valid()) return null;
          if (method == 'state') {
            return {
              'title': _heading,
              'revision': session.revision.toJson(),
              'busy': _busy || ConfigurationWindows.opened.value,
              'rows': [
                for (final entry in session.entries.where((entry) => !entry.isDeleted))
                  if (!entry.isEnvironment ||
                      entry.id ==
                          (_environmentId ??
                              session.entries.where((e) => e.isEnvironment && !e.isDeleted).firstOrNull?.id))
                    {
                      'id': entry.id,
                      'title': entry.title,
                      'kind': entry.kind.name,
                      'password': entry.hasPassword,
                      'username': entry.username.isNotEmpty,
                      'notes': !entry.isEnvironment && entry.notes.isNotEmpty,
                      'totp': entry.hasTotp,
                      if (entry.isEnvironment) 'keys': ProjectEnvironment.decode(entry.notes).variables.keys.toList(),
                    },
              ],
            };
          }
          if (_busy || ConfigurationWindows.opened.value || arguments is! Map) return false;
          final entry = session.entries.where((entry) => entry.id == arguments['id'] && !entry.isDeleted).firstOrNull;
          if (entry == null) return false;
          _touchActivity();
          if (method == 'reveal') {
            final selected =
                _environmentId ?? session.entries.where((e) => e.isEnvironment && !e.isDeleted).firstOrNull?.id;
            if (!entry.isEnvironment || entry.id != selected) return null;
            return ProjectEnvironment.decode(entry.notes).variables[arguments['key']];
          }
          if (method == 'edit') {
            unawaited(entry.isFile ? _openFile(entry) : _edit(entry));
            return true;
          }
          if (method == 'delete') {
            unawaited(_deleteEntry(entry));
            return true;
          }
          if (method == 'open') {
            if (entry.isFile) {
              unawaited(_openFile(entry));
            }
            if (entry.isSsh) {
              unawaited(_connectSsh(entry));
            }
            return true;
          }
          if (method == 'totp') {
            final codes = TotpSession(
              vault: session,
              isValid: valid,
              copy: widget.copySecret,
              clearClipboard: widget.clearClipboard,
              activity: _touchActivity,
            );
            try {
              return await codes.copyCode(entry.id, DateTime.now());
            } finally {
              codes.close();
            }
          }
          if (method == 'copyField') {
            final field = arguments['field'];
            final String? value;
            if (entry.isEnvironment) {
              final env = ProjectEnvironment.decode(entry.notes);
              value = field == 'env' ? ProjectDotenv.format(env) : env.variables[arguments['key']];
            } else {
              value = switch (field) {
                'password' => entry.password,
                'username' => entry.username,
                'notes' => entry.notes,
                _ => null,
              };
            }
            if (value == null) return false;
            final copied = await widget.copySecret(value);
            if (!valid() || !session.entries.contains(entry)) {
              await widget.clearClipboard();
              return false;
            }
            return copied;
          }
          return false;
        },
      );
    } catch (_) {
      if (valid()) _notice(t.configurationFailed);
    } finally {
      if (identical(_resourcesSession, session)) _resourcesSession = null;
    }
  }

  void showSection(bool projects) {
    if (_loading || _busy || _catalog == null) return;
    if (projects && !_lifecycle.workspaceUnlocked) {
      _notice(t.projectUnlockWorkspace, kind: DesktopNoticeKind.information);
      return;
    }
    if (_editor.active || _renamingVault || _master.text.isNotEmpty || _confirmation.text.isNotEmpty) {
      _notice(t.projectFinishEditing, kind: DesktopNoticeKind.information);
      return;
    }
    _lock(preserveWorkspace: true);
    setState(() => _projectsMode = projects);
    widget.onSectionChanged?.call(projects);
    if (!projects && _windowShown) onWindowShown();
  }

  Future<void> _createProject() async {
    if (_busy || !_lifecycle.workspaceUnlocked) return;
    final epoch = _securityEpoch;
    final data = await _configuration('project');
    final draft = data == null ? null : (name: data['name'] as String, password: data['password'] as String?);
    if (!mounted || draft == null || epoch != _securityEpoch) return;
    await _operation(() async {
      final created = await _lifecycle.createProject(draft.name, password: draft.password);
      if (created != null && mounted) setState(() => _archivedProjects = false);
      _touchActivity();
    });
    if (mounted && _error != null) _notice(_errorText);
  }

  void _launchChanged() {
    if (mounted) setState(() {});
  }

  String _launchId(VaultSession session, VaultEntry entry) => '${session.revision.lineage}/${entry.id}';

  Future<void> _loadLaunchProfiles() async {
    final session = _session;
    if (session == null || _lifecycle.project == null) return;
    try {
      final directory = await _launchPreferences.readDirectory(session.revision.lineage);
      if (!mounted || session.isLocked || session != _session) return;
      _projectDirectory = directory;
    } catch (_) {
      if (mounted && !session.isLocked) _notice(t.vaultPreferencesReadFailed);
      return;
    }
    for (final entry in session.entries.where((entry) => entry.isEnvironment && !entry.isDeleted)) {
      try {
        final profile = await _launchPreferences.read(_launchId(session, entry));
        if (!mounted || session.isLocked || _session != session) return;
        if (profile != null) _launchProfiles[entry.id] = profile;
      } catch (_) {
        if (mounted && !session.isLocked) _notice(t.vaultPreferencesReadFailed);
        return;
      }
    }
  }

  Future<void> _editEnvironment([VaultEntry? entry, bool duplicate = false]) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return;
    if (entry != null && !session.entries.contains(entry)) return;
    if (!duplicate &&
        entry != null &&
        (_projectLaunch.running(_launchId(session, entry)) || _projectLaunch.starting(_launchId(session, entry)))) {
      return;
    }
    await _configuration(
      'environment',
      data: {
        'creating': entry == null || duplicate,
        'name': duplicate ? t.projectEnvCopyName(name: entry!.title) : entry?.title ?? '',
        'variables': entry == null ? <String, String>{} : ProjectEnvironment.decode(entry.notes).variables,
      },
      onAction: (method, result) async {
        if (method != 'save' || result is! Map || !mounted || session.isLocked || session != _session) {
          return t.vaultWriteFailed;
        }
        final changed = VaultEntry(
          id: duplicate
              ? VaultEntry.create(title: result['name'] as String).id
              : entry?.id ?? VaultEntry.create(title: result['name'] as String).id,
          title: result['name'] as String,
          username: '',
          password: '',
          notes: result['contents'] as String,
          kind: VaultEntryKind.environment,
          folderId: entry?.folderId,
          order: entry?.order ?? 0,
          conflictOf: duplicate ? null : entry?.conflictOf,
          isFavorite: entry?.isFavorite ?? false,
        );
        if (await _persist([
          for (final item in session.entries)
            if (item.id != changed.id) item,
          changed,
        ])) {
          if (mounted) setState(() => _environmentId = changed.id);
          return null;
        }
        return t.vaultWriteFailed;
      },
    );
  }

  Future<void> _importProjectFolder() async {
    final session = _session;
    final store = _store;
    if (_busy || session == null || session.isLocked || store == null) return;
    bool valid() => mounted && identical(session, _session) && !session.isLocked;
    final directory = await getDirectoryPath(initialDirectory: _projectDirectory);
    if (directory == null || !valid()) return;
    List<ProjectEnvSource> sources = [];
    final imported = <int, String>{};
    try {
      await _operation(() async {
        sources = await ProjectEnvImport.scan(Directory(directory), allowed: valid);
        if (!valid()) return;
        await _launchPreferences.saveDirectory(session.revision.lineage, directory);
        if (valid()) setState(() => _projectDirectory = directory);
      });
      if (!valid()) return;
      if (sources.isEmpty) {
        _notice(t.projectEnvNone, kind: DesktopNoticeKind.information);
        return;
      }
      await _configuration(
        'projectImport',
        data: {
          'files': [
            for (final source in sources)
              {'name': source.name, 'invalid': source.invalid, 'count': source.environment?.variables.length ?? 0},
          ],
        },
        onAction: (method, arguments) async {
          if (!valid() || arguments is! List || arguments.isEmpty) return t.vaultWriteFailed;
          final indices = arguments.cast<int>().toSet();
          if (indices.any((index) => index < 0 || index >= sources.length || sources[index].environment == null)) {
            return t.vaultWriteFailed;
          }
          if (method == 'import' && imported.isEmpty) {
            final names = session.entries
                .where((entry) => entry.isEnvironment && !entry.isDeleted)
                .map((entry) => entry.title)
                .toSet();
            final entries = <VaultEntry>[];
            for (final index in indices) {
              var name = sources[index].name;
              if (name.length > 100) name = name.substring(name.length - 100);
              final base = name;
              for (var suffix = 2; names.contains(name); suffix++) {
                name = '$base ($suffix)';
              }
              names.add(name);
              final entry = VaultEntry(
                id: VaultEntry.create(title: name).id,
                title: name,
                username: '',
                password: '',
                notes: sources[index].environment!.encode(),
                kind: VaultEntryKind.environment,
              );
              entries.add(entry);
              imported[index] = entry.id;
            }
            if (!await _persist([...session.entries, ...entries])) {
              imported.clear();
              return t.vaultWriteFailed;
            }
            if (!valid()) return t.vaultWriteFailed;
            setState(() => _environmentId = entries.first.id);
            return true;
          }
          if (method == 'remove' && indices.every(imported.containsKey)) {
            // Authenticate and decode the bytes actually read back from disk before offering removal.
            final verified = await session.openRevision(await store.readEncryptedSnapshot());
            try {
              if (!valid()) return t.vaultWriteFailed;
              for (final index in indices) {
                final entry = verified.entries
                    .where((entry) => entry.id == imported[index] && !entry.isDeleted)
                    .firstOrNull;
                if (entry == null || entry.notes != sources[index].environment!.encode()) {
                  return t.projectEnvDeleteFailed;
                }
              }
              for (final index in indices) {
                if (!await sources[index].removeUnchanged(allowed: valid)) return t.projectEnvDeleteFailed;
              }
              return true;
            } finally {
              session.closeRevision(verified);
            }
          }
          return t.vaultWriteFailed;
        },
      );
    } catch (_) {
      if (valid()) _notice(t.projectEnvImportFailed);
    } finally {
      for (final source in sources) {
        source.clear();
      }
    }
  }

  Future<void> _configureLaunch(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || !session.entries.contains(entry)) return;
    await _configuration(
      'launch',
      data: _launchProfiles[entry.id]?.toJson() ?? {'directory': _projectDirectory ?? ''},
      onAction: (method, result) async {
        if (method != 'save' || result is! Map || !mounted || session.isLocked || session != _session) {
          return t.vaultPreferencesSaveFailed;
        }
        try {
          final profile = ProjectLaunchProfile.fromJson(result);
          profile.checkSecrets(ProjectEnvironment.decode(entry.notes).variables.values);
          await _launchPreferences.save(_launchId(session, entry), profile);
          if (mounted && !session.isLocked && session == _session) {
            setState(() => _launchProfiles[entry.id] = profile);
          }
          return null;
        } catch (_) {
          return t.projectLaunchInvalid;
        }
      },
    );
  }

  Future<void> _runEnvironment(VaultEntry entry) async {
    final session = _session;
    final profile = _launchProfiles[entry.id];
    if (_busy || session == null || session.isLocked || profile == null || !session.entries.contains(entry)) return;
    if (!await _confirm(
      t.projectLaunchReview,
      '${entry.title}\n\n${profile.executable}\n${profile.directory}\n\n${t.projectLaunchTrust}',
      actionLabel: t.projectLaunch,
    )) {
      return;
    }
    if (!mounted || session.isLocked || session != _session) return;
    _touchActivity();
    try {
      final started = await _projectLaunch.start(
        id: _launchId(session, entry),
        session: session,
        entry: entry,
        profile: profile,
      );
      if (!started && mounted && !session.isLocked) _notice(t.projectLaunchFailed);
    } catch (_) {
      if (mounted && !session.isLocked) _notice(t.projectLaunchFailed);
    }
  }

  Future<void> _openProject(VaultProject project) async {
    if (_busy || !_lifecycle.workspaceUnlocked) return;
    if (project.conflictOf != null) {
      final epoch = _securityEpoch;
      if (!await _confirm(t.projectConflict, t.projectResolveQuestion(name: project.name)) ||
          !mounted ||
          epoch != _securityEpoch) {
        return;
      }
      VaultProject? resolved;
      await _operation(() async {
        resolved = await _lifecycle.resolveProject(project);
      });
      if (resolved == null || !mounted || epoch != _securityEpoch) return;
      project = resolved!;
    }
    _lock(preserveWorkspace: true);
    setState(() {
      _projectsMode = true;
      _openingProjectId = project.id;
      _environmentId = null;
      _loading = true;
    });
    widget.onSectionChanged?.call(true);
    final opening = _lifecycle.selectProject(project);
    final epoch = _securityEpoch;
    try {
      await opening;
      if (!mounted || epoch != _securityEpoch) return;
      _restoreTreeState();
      await _loadLaunchProfiles();
      _touchActivity();
      if (mounted) onWindowShown();
    } on VaultUnlockException {
      if (mounted && epoch == _securityEpoch) _error = 'unlock';
    } catch (_) {
      if (mounted && epoch == _securityEpoch) _error = 'io';
    } finally {
      if (mounted && epoch == _securityEpoch) {
        setState(() {
          _loading = false;
          _openingProjectId = null;
        });
      }
    }
  }

  Future<void> _restoreArchivedProject(VaultProject project) async {
    if (_busy || !_lifecycle.workspaceUnlocked) return;
    final epoch = _securityEpoch;
    if (!await _confirm(
          t.projectUnarchive,
          t.projectUnarchiveQuestion(name: project.name),
        ) ||
        !mounted ||
        epoch != _securityEpoch) {
      return;
    }
    await _operation(() => _lifecycle.toggleProjectArchive(project));
    if (mounted && _error != null) _notice(_errorText);
  }

  Future<void> _deleteProject(VaultProject project) async {
    if (_busy || _loading || !_lifecycle.workspaceUnlocked) return;
    final epoch = _securityEpoch;
    if (!await _confirm(t.projectRemove, t.projectRemoveQuestion(name: project.name)) ||
        !mounted ||
        epoch != _securityEpoch) {
      return;
    }
    await _operation(() async {
      await _projectLaunch.stopProject(project.lineage);
      if (!mounted || epoch != _securityEpoch) return;
      if (_lifecycle.projects.every((p) => p.id == project.id || p.lineage != project.lineage)) {
        await _launchPreferences.removeProject(project.lineage);
      }
      if (!mounted || epoch != _securityEpoch) return;
      await _lifecycle.deleteProject(project);
    });
    if (mounted && _error != null) _notice(_errorText);
  }

  Future<void> _restoreProject() async {
    if (_busy || _lifecycle.project == null) return;
    final epoch = _securityEpoch;
    await _operation(() async {
      final source = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: t.appName, extensions: ['smv']),
        ],
      );
      if (!mounted || source == null || epoch != _securityEpoch) return;
      if (_lifecycle.project!.unlockWithWorkspace) {
        try {
          if (await _lifecycle.restoreProject(File(source.path))) {
            _restoreTreeState();
            await _loadLaunchProfiles();
            _touchActivity();
            return;
          }
        } on VaultUnlockException {
          if (!mounted || epoch != _securityEpoch) return;
        }
      }
      final passwords = await _passwordPrompt();
      if (!mounted || passwords == null || epoch != _securityEpoch) return;
      await _lifecycle.restoreProject(File(source.path), password: passwords.password);
      _restoreTreeState();
      await _loadLaunchProfiles();
      _touchActivity();
    });
  }

  Future<bool> _confirmSshHost(String prompt) async {
    if (!mounted || _session == null || _session!.isLocked || _sensitiveDialogOpen) return false;
    return _confirm(t.sshHostKeyTitle, '${t.sshHostKeyHelp}\n\n$prompt', actionLabel: t.sshTrustHost);
  }

  Future<void> _connectSsh(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || entry.isDeleted) return;
    try {
      await _sshConnections.start(_selectedVaultId ?? 'local', session, entry);
      if (mounted && _session == session && !session.isLocked) {
        _notice(t.sshStarted, kind: DesktopNoticeKind.success);
      }
    } on PlatformException catch (error) {
      if (!mounted || _session != session || session.isLocked) return;
      _notice(switch (error.code) {
        'missing' => t.sshMissing,
        'active' => t.sshActive,
        'limit' => t.sshLimit,
        'invalid' => t.sshInvalid,
        _ => t.sshFailed,
      });
    } catch (_) {
      if (mounted && _session == session && !session.isLocked) {
        _notice(t.sshFailed);
      }
    }
  }

  Future<void> synchronize(GitHubBackup backup) async {
    if (_busy || _loading || backup.busy) return;
    if (_editor.active || _renamingVault || _viewers.hasOpenViewers) {
      _notice(t.syncFinishEditing, kind: DesktopNoticeKind.information);
      return;
    }
    if (!backup.signedIn) {
      await showGitHub(backup);
      return;
    }
    final session = _session;
    if (session == null || session.isLocked || _selectedVaultId == null) {
      _notice(t.syncUnlock, kind: DesktopNoticeKind.information);
      await showGitHub(backup);
      return;
    }
    final epoch = _securityEpoch;
    _touchActivity();
    var openRemoteCopy = false;
    _resetBrowser();
    await _operation(() async {
      final result = await _sync.synchronize(backup);
      if (!mounted || epoch != _securityEpoch || session.isLocked) return;
      if (result == VaultSyncResult.unavailable) return;
      setState(() {});
      final message = _synchronizationMessage(backup, result);
      if (!backup.syncKeyChanged) {
        _notice(
          message,
          kind: switch (result) {
            VaultSyncResult.done => DesktopNoticeKind.success,
            VaultSyncResult.failed || VaultSyncResult.rollback => DesktopNoticeKind.error,
            _ => DesktopNoticeKind.warning,
          },
        );
        return;
      }
      openRemoteCopy = await _confirm(t.syncKeyChangedTitle, message, actionLabel: t.syncOpenRemoteCopy);
    }, showProgress: false);
    if (openRemoteCopy && mounted && epoch == _securityEpoch) {
      await showGitHub(backup, restoreSeparately: true);
    }
  }

  String _synchronizationMessage(GitHubBackup backup, VaultSyncResult result) => switch (result) {
    VaultSyncResult.keyChanged => t.syncKeyChanged,
    VaultSyncResult.rollback => t.syncRollback,
    VaultSyncResult.failed => backup.problem == null ? t.githubRestoreError : GitHubLabels.problem(backup.problem!),
    VaultSyncResult.cleanupPending => t.vaultSnapshotCleanupWarning,
    VaultSyncResult.conflicts => t.syncConflicts(count: backup.mergedConflicts),
    VaultSyncResult.done => t.syncDone,
    VaultSyncResult.unavailable => t.syncUnlock,
  };

  Future<void> showGitHub(GitHubBackup backup, {bool restoreSeparately = false}) async {
    if (_busy || _loading || _editor.active || _catalog == null) return;
    await _showGitHubDialog(backup, restoreSeparately: restoreSeparately);
  }

  Future<void> _showGitHubDialog(GitHubBackup backup, {required bool restoreSeparately}) async {
    final dialog = GitHubDialog(
      backup: backup,
      restoreSeparately: restoreSeparately,
      linkExisting: restoreSeparately || _session == null
          ? null
          : (remote) async {
              final session = _session;
              final store = _store;
              final id = _selectedVaultId;
              final epoch = _securityEpoch;
              if (session == null || store == null || id == null || session.isLocked) {
                return false;
              }
              if (!await _confirm(t.syncRelink, t.syncRelinkHelp) || !mounted || epoch != _securityEpoch) {
                return false;
              }
              _resetBrowser();
              final linked = await _sync.link(backup, remote);
              if (!mounted || epoch != _securityEpoch) return false;
              if (linked == false) {
                final problem = backup.problem;
                _notice(
                  backup.syncKeyChanged
                      ? t.syncKeyChanged
                      : problem == null
                      ? t.syncUnlock
                      : GitHubLabels.problem(problem),
                );
                return false;
              }
              _notice(t.syncRelinkDone, kind: DesktopNoticeKind.success);
              return true;
            },
      restore: (bytes, remote) async {
        if (remote != null) {
          final existing = backup.localForRemote(remote.id);
          final reference = (await _catalog!.list()).where((v) => v.id == existing).firstOrNull;
          if (reference != null) {
            if (reference.isProject) {
              final project = _lifecycle.projects.where((p) => p.vaultId == existing).firstOrNull;
              if (project == null) {
                if (mounted) _notice(t.projectSelectWorkspace, kind: DesktopNoticeKind.information);
                return false;
              }
              await _openProject(project);
            } else {
              await _selectVault(existing);
            }
            if (mounted) _notice(t.syncAlreadyLinked, kind: DesktopNoticeKind.information);
            return true;
          }
        }
        final epoch = _securityEpoch;
        final intoProject = !restoreSeparately && _lifecycle.project != null;
        final shared = intoProject && _lifecycle.project!.unlockWithWorkspace;
        final passwords = shared ? (current: '', password: '') : await _passwordPrompt();
        if (passwords == null || !mounted || epoch != _securityEpoch) {
          return false;
        }
        var restored = false;
        await _operation(() async {
          if (await _sync.restore(backup, bytes, passwords.password, remote: remote, intoProject: intoProject) ==
                  false ||
              !mounted) {
            return;
          }
          _resetBrowser();
          _viewers.closeAll();
          _codesWindow.close();
          unawaited(widget.clearClipboard());
          setState(() {
            _master.clear();
            _confirmation.clear();
            _vaultName.clear();
            _clearEditor();
          });

          _touchActivity();
          restored = true;
        });
        if (!restored && mounted && epoch == _securityEpoch) {
          _notice(t.githubRestoreError);
        }
        return restored;
      },
    );
    try {
      await _configuration(
        'github',
        data: {
          'snapshot': GitHubSettingsController.snapshot(backup),
          'separately': restoreSeparately,
          'link': dialog.linkExisting != null,
        },
        onAction: (method, value) async {
          switch (method) {
            case 'state':
              break;
            case 'connect':
              final data = value as Map;
              await backup.connectToken(
                data['token'] as String,
                data['repository'] as String,
                initializeRepository: data['initialize'] == true,
              );
            case 'recover':
              await backup.resetDamagedConnection();
            case 'discover':
              await backup.discover();
            case 'backup':
              await backup.sync();
            case 'keepBoth':
              await backup.keepBoth();
            case 'disconnect':
              await backup.disconnect();
            case 'link':
              final remote = backup.remoteVaults.where((item) => item.id == value).firstOrNull;
              return remote != null && await dialog.linkExisting?.call(remote) == true;
            case 'restore':
              final remote = backup.remoteVaults.where((item) => item.id == (value as Map)['id']).firstOrNull;
              if (remote == null) return false;
              final bytes = await backup.download(remote);
              if (bytes == null) return false;
              return dialog.restore(bytes, (value as Map)['link'] == true ? remote : null);
            default:
              return null;
          }
          return GitHubSettingsController.snapshot(backup);
        },
      );
    } finally {
      backup.cancelConnection();
    }
  }

  Object? get fileDropSession => _session;

  String? get fileDropFolderId => _treeKey.currentState?.nativeFolderId;

  void updateFileDropPosition(Offset? position) {
    _treeKey.currentState?.nativeHover(canAcceptFileDrop ? position : null);
  }

  bool get canAcceptFileDrop =>
      _contentActive &&
      !_loading &&
      _session != null &&
      !_session!.isLocked &&
      !_busy &&
      !_editor.active &&
      _browser.filtering == false &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  String get fileDropHint => _session == null || _session!.isLocked
      ? t.vaultDropLocked
      : (_busy || _editor.active || ConfigurationWindows.opened.value || !(ModalRoute.of(context)?.isCurrent ?? true))
      ? t.vaultDropBusy
      : t.vaultDropHint;

  Future<void> importDroppedFiles(
    List<String> paths, {
    required Object? sessionToken,
    String? folderId,
  }) async {
    if (_session != sessionToken || !canAcceptFileDrop) {
      _notice(fileDropHint, kind: DesktopNoticeKind.information);
      return;
    }
    final session = _session!;
    if (folderId != null && session.folders.every((folder) => folder.id != folderId)) return;
    await _operation(() => _importFiles(session, paths, folderId: folderId));
  }

  Future<void> _importFiles(
    VaultSession session,
    List<String> paths, {
    String? folderId,
  }) async {
    try {
      final entries = await VaultFileImport.read(session, paths, folderId: folderId);
      if (entries.isEmpty || !mounted || session.isLocked || _session != session) {
        return;
      }
      final organization = VaultOrganization(entries: session.entries, folders: session.folders);
      organization.prependEntries(entries, folderId);
      if (await _lifecycle.save(organization.entries, folders: organization.folders) == false) return;
      if (mounted && !session.isLocked && _session == session) {
        setState(() => _collapsedFolders.remove(folderId ?? ''));
        _notice(t.vaultFilesAdded(count: entries.length), kind: DesktopNoticeKind.success);
      }
    } on FileImportException catch (error) {
      if (!mounted || session.isLocked || _session != session) return;
      _notice(switch (error.problem) {
        FileImportProblem.limit => t.vaultAttachmentLimit,
        FileImportProblem.name => t.vaultInvalidFilename,
        FileImportProblem.notFile => t.vaultDropFilesOnly,
        FileImportProblem.changed => t.vaultDropChanged,
      });
    }
  }

  void onWindowHidden() {
    _windowShown = false;
    _restoreCodesPending = false;
    ConfigurationWindows.closeAll();
    _resourcesSession = null;
    _cancelPasswordGeneration();
    _externalDragCandidate = null;
    _fileDrag.cancel();
    _secretDrag.cancel();
    _codesWindow.close();
    _searchWindow.close();
    DesktopMenuObserver.dismissAll();
    if (!mounted) return;
    if (!_lockWhenHidden) {
      setState(() {});
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _lock(clearClipboard: false, keepNotice: true);
  }

  void lockFromHeader() => _lock();

  void _configurationChanged() {
    _updateSearchHandler();
    if (ConfigurationWindows.opened.value) {
      _restoreCodesPending = false;
      _searchWindow.close();
      _codesWindow.close();
    } else {
      _restoreCodesPending = _windowShown;
      unawaited(_restoreCodesAfterConfiguration());
    }
  }

  Future<void> _restoreCodesAfterConfiguration() async {
    if (!_windowShown || !_restoreCodesPending || _busy) return;
    try {
      if (await windowManager.isVisible() && mounted && _windowShown && _contentActive && !_busy) {
        _restoreCodesPending = false;
        onWindowShown();
      }
    } catch (_) {}
  }

  void onWindowShown() {
    _windowShown = true;
    if (!_contentActive) return;
    if (_lifecycle.project != null) {
      unawaited(_openProjectSecrets());
      return;
    }
    if (_session?.entries.any((entry) => entry.hasTotp && entry.isDeleted == false) == true) {
      unawaited(_openCodes());
    }
  }

  @override
  void initState() {
    super.initState();
    ConfigurationWindows.onActivity = _touchActivity;
    ConfigurationWindows.opened.addListener(_configurationChanged);
    _projectLaunch.addListener(_launchChanged);
    _lifecycle = VaultSessionController(store: widget.store, catalog: widget.catalog);
    _sync = VaultSyncController(_lifecycle);
    _sshConnections = SshConnections(
      confirmHost: _confirmSshHost,
      onAuthorizationChanged: (pending) => widget.onSshAuthorizationChanged?.call(pending),
      onExit: (success) {
        if (mounted) {
          _notice(
            success ? t.sshClosed : t.sshFailed,
            kind: success ? DesktopNoticeKind.information : DesktopNoticeKind.error,
          );
        }
      },
    );
    HardwareKeyboard.instance.addHandler(_onKeyActivity);
    FocusManager.instance.addListener(_updateSearchHandler);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerActivity);
    _systemLock.setMethodCallHandler((call) async {
      if (call.method == 'lock' && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _lock();
      }
    });
    unawaited(_checkSystemLock());
    unawaited(
      DesktopStartup.track(
        'totp',
        () => _codesWindow.prepare(
          LocaleSettings.currentLocale.languageCode,
        ),
      ).catchError((_) {}),
    );
    unawaited(DesktopStartup.track('search', _searchWindow.prepare).catchError((_) {}));
    unawaited(
      DesktopStartup.track('vault', () async {
        await _load();
        if (_error == 'read') throw StateError('Vault catalog unavailable');
      }).catchError((_) {}),
    );
  }

  @override
  void didUpdateWidget(VaultPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == false) _searchWindow.close();
    if (widget.active == false) _codesWindow.close();
    if (widget.active == false) {
      _fileDrag.cancel();
      _secretDrag.cancel();
    }
    if (widget.active && oldWidget.active == false) onWindowShown();
  }

  Future<void> _checkSystemLock() async {
    try {
      final ready = await _systemLock.invokeMethod<bool>('ready');
      if (mounted && ready == false) _notice(t.vaultSystemLockFailed);
    } on MissingPluginException catch (_) {
    } catch (_) {
      if (mounted) _notice(t.vaultSystemLockFailed);
    }
  }

  void _notice(String message, {DesktopNoticeKind kind = DesktopNoticeKind.error}) {
    if (mounted) DesktopNoticeHost.show(context, message, kind: kind);
  }

  Future<VaultPasswords?> _passwordPrompt({
    bool change = false,
  }) async {
    _sensitiveDialogOpen = true;
    setState(() => _waitingForPassword = true);
    try {
      final result = await _configuration('password', data: {'change': change});
      return result == null ? null : (current: result['current'] as String, password: result['password'] as String);
    } finally {
      _sensitiveDialogOpen = false;
      if (mounted) setState(() => _waitingForPassword = false);
    }
  }

  Future<void> _operation(Future<void> Function() action, {bool showProgress = true}) async {
    if (_busy) return;
    final epoch = _securityEpoch;
    setState(() {
      _busy = true;
      _busyProgress = showProgress;
      _error = null;
    });
    try {
      await action();
    } on MasterPasswordPolicyException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'password-policy');
      }
    } on MemoryProtectionException {
      if (mounted && epoch == _securityEpoch) {
        setState(() => _error = 'memory-protection');
      }
    } on VaultUnlockException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'unlock');
    } on VaultFormatException {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'format');
    } on VaultConflictException {
      if (mounted && epoch == _securityEpoch) _notice(t.vaultDestinationExists, kind: DesktopNoticeKind.information);
    } catch (_) {
      if (mounted && epoch == _securityEpoch) setState(() => _error = 'io');
    } finally {
      if (mounted && epoch == _securityEpoch) {
        setState(() {
          _busy = false;
          _busyProgress = true;
        });
      }
    }
  }

  Future<void> _importVault({File? snapshot}) async {
    if (_catalog == null || _busy) return;
    final epoch = _securityEpoch;
    await _operation(() async {
      final source = snapshot != null
          ? XFile(snapshot.path)
          : await openFile(
              acceptedTypeGroups: [
                XTypeGroup(label: t.vaultAllFiles),
                XTypeGroup(label: t.appName, extensions: const ['smv']),
              ],
            );
      if (!mounted || source == null || epoch != _securityEpoch) return;
      final passwords = await _passwordPrompt();
      if (!mounted || passwords == null || epoch != _securityEpoch) return;
      if (await _lifecycle.importFile(File(source.path), passwords.password) == false || !mounted) return;
      _resetBrowser();
      _viewers.closeAll();
      _codesWindow.close();
      unawaited(widget.clearClipboard());
      setState(() {
        _master.clear();
        _confirmation.clear();
        _vaultName.clear();
        _clearEditor();
      });

      _touchActivity();
      _notice(t.vaultImportDone, kind: DesktopNoticeKind.success);
    });
  }

  Future<void> _exportVault() async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      VaultSession? exportCopy;
      try {
        if (_lifecycle.project?.unlockWithWorkspace == true) {
          final epoch = _securityEpoch;
          final data = await _configuration('password', data: {'create': true});
          final password = data == null
              ? null
              : (current: data['current'] as String, password: data['password'] as String);
          if (!mounted || password == null || epoch != _securityEpoch || session.isLocked) return;
          exportCopy = await session.exportWithPassword(password.password);
          if (!mounted || epoch != _securityEpoch || session.isLocked) return;
        } else if (session.projects.isNotEmpty) {
          if (!await _confirm(t.vaultExport, t.projectBackupHelp) || !mounted || session.isLocked) return;
        }
        final destination = await SaveFileDialog.select(
          context: context,
          suggestedName: 'vault-backup-${DateTime.now().millisecondsSinceEpoch}.smv',
          requireExtension: true,
          allowed: () => mounted && !session.isLocked && _session == session,
        );
        if (!mounted || destination == null || session.isLocked || _session != session) {
          return;
        }
        await _store!.exportTo(
          exportCopy ?? session,
          destination,
          allowed: () => mounted && !session.isLocked && _session == session,
        );
        if (mounted && !session.isLocked) _notice(t.vaultExportDone, kind: DesktopNoticeKind.success);
      } finally {
        if (exportCopy != null) session.closeRevision(exportCopy);
      }
    });
  }

  Future<void> _changePassword() async {
    if (_lifecycle.project?.unlockWithWorkspace == true) {
      showSection(false);
      if (_lifecycle.project != null) return;
    }
    final session = _session;
    if (session == null || _busy) return;
    await _operation(() async {
      final passwords = await _passwordPrompt(change: true);
      if (!mounted || passwords == null || session.isLocked || _session != session) {
        return;
      }
      _resetBrowser();
      if (await _lifecycle.changePassword(passwords.current, passwords.password) == false || !mounted) return;
      setState(() {});
      _viewers.closeAll();
      _codesWindow.close();
      unawaited(widget.clearClipboard());

      _touchActivity();
      _notice(
        _store!.snapshotCleanupPending ? t.vaultSnapshotCleanupWarning : t.vaultPasswordChanged,
        kind: _store!.snapshotCleanupPending ? DesktopNoticeKind.warning : DesktopNoticeKind.success,
      );
    });
  }

  Future<void> _createTextFile([String? folderId]) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || _sensitiveDialogOpen) return;
    VaultEntry? created;
    _sensitiveDialogOpen = true;
    try {
      final accepted = await _configuration(
        'text',
        onAction: (method, arguments) async {
          if (method != 'create' || arguments is! String) return t.vaultWriteFailed;
          final name = arguments;
          if (!mounted || _session != session || session.isLocked || _busy) return t.vaultWriteFailed;
          try {
            final organization = VaultOrganization(entries: session.entries, folders: session.folders);
            final entry = VaultTextFile.prepare(name: name, organization: organization, folderId: folderId);
            if (!await _persist(organization.entries, folders: organization.folders)) return t.vaultWriteFailed;
            if (!mounted || _session != session || session.isLocked) return t.vaultWriteFailed;
            created = session.entries.firstWhere((candidate) => candidate.id == entry.id);
            setState(() {
              _collapsedFolders.remove(folderId);
              final parent = session.folders.where((folder) => folder.id == folderId).firstOrNull?.parentId;
              _collapsedFolders.remove(parent);
            });
            return null;
          } on TextFileException catch (error) {
            return switch (error.problem) {
              TextFileProblem.invalidName => t.vaultTextNameInvalid,
              TextFileProblem.nameTaken => t.vaultTextNameTaken,
              TextFileProblem.limit => t.vaultLimit,
              TextFileProblem.location => t.vaultWriteFailed,
            };
          } on MemoryProtectionException {
            return t.vaultMemoryProtectionFailed;
          } catch (_) {
            return t.vaultWriteFailed;
          }
        },
      );
      if (mounted && accepted == true && _session == session && !session.isLocked && created != null) {
        await _openFile(created!);
      }
    } finally {
      _sensitiveDialogOpen = false;
    }
  }

  Future<void> _addFile([String? folderId]) async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      final selected = await openFile();
      if (!mounted || selected == null || session.isLocked || _session != session) {
        return;
      }
      await _importFiles(session, [selected.path], folderId: folderId);
    });
  }

  Future<void> _extractAttachment(VaultAttachment attachment) async {
    final session = _session;
    if (session == null) return;
    await _operation(() async {
      final destination = await SaveFileDialog.select(
        context: context,
        suggestedName: attachment.name,
        allowed: () => mounted && !session.isLocked && _session == session,
      );
      if (!mounted || destination == null || session.isLocked || _session != session) {
        return;
      }
      await VaultStore.extract(session, attachment, destination);
      if (mounted && !session.isLocked) _notice(t.vaultAttachmentSaved, kind: DesktopNoticeKind.success);
    });
  }

  Future<void> _openFile(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || !entry.isFile || entry.isDeleted) return;
    var original = entry.attachments.single;
    final bytes = original.bytes;
    final TextDocument? document;
    try {
      document = TextDocument.decode(original.name, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final readable = document;
    if (readable == null) {
      _notice(t.fileEditorUnsupported, kind: DesktopNoticeKind.information);
      await _extractAttachment(original);
      return;
    }
    await _operation(
      () => _viewers.open(
        id: entry.id,
        name: original.name,
        text: readable.text,
        encoding: readable.encoding,
        locale: LocaleSettings.currentLocale.languageCode,
        isValid: () =>
            mounted &&
            _session == session &&
            !session.isLocked &&
            session.entries.any((e) => e.id == entry.id && e.isDeleted == false),
        activity: _touchActivity,
        copy: widget.copySecret,
        clearClipboard: widget.clearClipboard,
        save: (text) async {
          if (!mounted || _session != session || session.isLocked || _busy) {
            return false;
          }
          final current = session.entries.where((e) => e.id == entry.id).firstOrNull;
          if (current == null ||
              current.isDeleted ||
              !current.isFile ||
              !identical(current.attachments.single, original)) {
            return false;
          }
          try {
            final encoded = readable.encode(text);
            final VaultAttachment updated;
            try {
              updated = VaultAttachment(
                id: original.id,
                name: original.name,
                bytes: encoded,
              );
            } finally {
              encoded.fillRange(0, encoded.length, 0);
            }
            final replacement =
                VaultEntry.file(
                      updated,
                      id: current.id,
                      folderId: current.folderId,
                    )
                    .withFavorite(current.isFavorite)
                    .withConflict(current.conflictOf)
                    .atPosition(current.folderId, current.order);
            if (!await _persist(
              session.entries.map((e) => e.id == entry.id ? replacement : e).toList(),
            )) {
              return false;
            }
            original = updated;
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }

  Future<void> _load() async {
    final epoch = _securityEpoch;
    try {
      await _lifecycle.load();
      if (!mounted || epoch != _securityEpoch) return;
      if (_preferences == null) {
        _preferences =
            widget.preferences ??
            VaultPreferences(
              file: _catalog == null
                  ? null
                  : File('${_catalog!.directory.path}${Platform.pathSeparator}vault_preferences.json'),
            );
        try {
          _autoLockEnabled = await _preferences!.loadAutoLock();
          _lockWhenHidden = _preferences!.lockWhenHidden;
        } catch (_) {
          _autoLockEnabled = true;
          _lockWhenHidden = true;
          if (mounted) _notice(t.vaultPreferencesReadFailed);
        }
      }
      if (_treePreferences == null) {
        final preferences = VaultTreePreferences(
          file: _catalog == null
              ? null
              : File('${_catalog!.directory.path}${Platform.pathSeparator}tree_preferences.json'),
        );
        try {
          await preferences.load();
          _treePreferences = preferences;
        } catch (_) {
          if (mounted) _notice(t.vaultPreferencesReadFailed);
        }
      }
      if (mounted && epoch == _securityEpoch) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && epoch == _securityEpoch) {
        setState(() {
          _loading = false;
          _error = 'read';
        });
      }
    }
  }

  Future<void> _open() async {
    if (_busy) return;
    if (_lifecycle.project?.unlockWithWorkspace == true) {
      await _operation(() async {
        if (await _lifecycle.open(_lifecycle.project!.credential) == false || !mounted) return;
        _restoreTreeState();
        await _loadLaunchProfiles();
        _touchActivity();
      });
      if (mounted) onWindowShown();
      return;
    }
    if (_master.text.isEmpty) {
      setState(() => _error = 'required');
      return;
    }
    if (!_exists && _master.text != _confirmation.text) {
      setState(() => _error = 'mismatch');
      return;
    }
    final password = _master.text;
    final name = _vaultName.text.trim();
    _master.clear();
    _confirmation.clear();
    await _operation(() async {
      if (await _lifecycle.open(password, name: name.isEmpty ? null : name) == false || !mounted) return;
      _restoreTreeState();
      await _loadLaunchProfiles();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(_vaultName.clear);
      _touchActivity();
      if (_store!.snapshotCleanupPending) _notice(t.vaultSnapshotCleanupWarning, kind: DesktopNoticeKind.warning);
    });
    if (_lifecycle.project != null) {
      unawaited(_openProjectSecrets());
      return;
    }
    if (_session?.entries.any((entry) => entry.hasTotp && entry.isDeleted == false) == true) unawaited(_openCodes());
  }

  bool _onKeyActivity(KeyEvent event) {
    _touchActivity();
    if (_contentActive == false ||
        _session == null ||
        _session!.isLocked ||
        _busy ||
        _editor.active ||
        _renamingVault) {
      return false;
    }
    if (event is KeyDownEvent && (ModalRoute.of(context)?.isCurrent ?? false)) {
      final keyboard = HardwareKeyboard.instance;
      final focus = FocusManager.instance.primaryFocus?.context;
      final editingText = focus?.findAncestorStateOfType<EditableTextState>() != null;
      if (editingText) return false;
      final shortcut = widget.searchShortcut?.call() ?? SystemShortcuts.defaultSearch();
      final modifiers = shortcut.modifiers ?? [];
      if (event.physicalKey == shortcut.physicalKey &&
          keyboard.isControlPressed == modifiers.contains(HotKeyModifier.control) &&
          keyboard.isAltPressed == modifiers.contains(HotKeyModifier.alt) &&
          keyboard.isShiftPressed == modifiers.contains(HotKeyModifier.shift) &&
          keyboard.isMetaPressed == modifiers.contains(HotKeyModifier.meta)) {
        unawaited(_startSearch());
        return true;
      }
    }
    return false;
  }

  Future<void> _startSearch() async {
    final session = _session;
    if (session == null || session.isLocked || _busy || _editor.active || _renamingVault || _searching) return;

    bool valid() => mounted && _contentActive && _session == session && session.isLocked == false;
    setState(() => _searching = true);
    widget.onSearchHandlerChanged?.call(null);
    try {
      final id = await _searchWindow.open(
        isValid: valid,
        find: (query) => _browser.suggestions(session, query),
        activity: _touchActivity,
        onBlur: () => widget.onCodesBlur?.call(),
        copy: widget.copySecret,
        clearClipboard: widget.clearClipboard,
      );
      if (valid() == false || _busy || _editor.active) return;
      if (id == null) return;
      final entry = session.entries.where((entry) => entry.id == id && entry.isDeleted == false).firstOrNull;
      if (entry == null) return;
      if (entry.isFile) {
        await _openFile(entry);
      } else if (entry.isSsh) {
        await _connectSsh(entry);
      } else if (entry.isTotp) {
        await _openCodes();
      } else if (entry.hasPassword) {
        await _copyEntry(entry);
      } else {
        await windowManager.focus();
        if (valid() == false || _busy || _editor.active) return;
        _edit(entry);
      }
    } catch (_) {
      if (valid()) _notice(t.searchUnavailable);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _requestSearch() {
    if (_canSearch) unawaited(_startSearch());
  }

  bool get _canSearch {
    final focus = FocusManager.instance.primaryFocus?.context;
    final editing = focus?.findAncestorStateOfType<EditableTextState>() != null;
    return mounted &&
        _contentActive &&
        _session?.isLocked == false &&
        !_busy &&
        !_editor.active &&
        !_renamingVault &&
        !_searching &&
        !_sensitiveDialogOpen &&
        !editing &&
        (ModalRoute.of(context)?.isCurrent ?? false);
  }

  void _updateSearchHandler() {
    if (mounted) widget.onSearchHandlerChanged?.call(_canSearch ? _requestSearch : null);
  }

  void _restoreTreeState() {
    if (_session == null || _session!.isLocked) return;
    final vaultId = _selectedVaultId ?? 'local';
    _treeState.restore(vaultId, _treePreferences?.collapsed(vaultId) ?? {});
  }

  void _saveTreeState() {
    final preferences = _treePreferences;
    if (preferences == null) return;
    unawaited(
      preferences.save(_selectedVaultId ?? 'local', _collapsedFolders).catchError((_) {
        if (mounted) _notice(t.vaultPreferencesSaveFailed);
      }),
    );
  }

  void _resetBrowser({bool keepNotice = false}) {
    _projectLaunch.lock();
    _openingProjectId = null;
    _projectDirectory = null;
    _cancelPasswordGeneration();
    _externalDragCandidate = null;
    _fileDrag.cancel();
    _secretDrag.cancel();
    _searchWindow.close();
    _browser.clear();
    _deletions.clear();
    _deletedEntries.clear();
    _deletionTimer?.cancel();
    _deletionTimer = null;
    if (!keepNotice) DesktopNoticeHost.clear(context);
  }

  void _onPointerActivity(PointerEvent event) {
    _touchActivity();
    if (event is PointerDownEvent) _updateSearchHandler();
    final candidate = _externalDragCandidate;
    if (candidate == null || event.pointer != candidate.pointer) return;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _externalDragCandidate = null;
      return;
    }
    if (event is! PointerMoveEvent || event.buttons != kPrimaryMouseButton || !mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = overlay.globalToLocal(event.position);
    if ((Offset.zero & overlay.size).contains(position) || (event.position - candidate.origin).distanceSquared < 16) {
      return;
    }
    _externalDragCandidate = null;
    GestureBinding.instance.cancelPointer(event.pointer);
    scheduleMicrotask(() {
      if (!mounted) return;
      if (candidate.entry.isFile) {
        unawaited(_dragFileOut(candidate.entry));
      } else {
        unawaited(_dragSecretOut(candidate.entry));
      }
    });
  }

  void _touchActivity() {
    if (!_lifecycle.hasOpenSession || !_autoLockEnabled) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 2), () {
      if (!mounted || !_lifecycle.hasOpenSession) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _lock();
    });
  }

  Future<void> _showPreferences() async {
    final previousCapture = _preferences?.captureAllowed ?? false;
    final data = await _configuration(
      'preferences',
      data: {
        'idle': _autoLockEnabled,
        'hidden': _lockWhenHidden,
        'capture': previousCapture,
        'manage': _session != null,
        'workspace': _lifecycle.project?.unlockWithWorkspace == true,
      },
    );
    if (data == null || !mounted) return;
    if (data['action'] == 'export') return _exportVault();
    if (data['action'] == 'password') return _changePassword();
    final result = (idle: data['idle'] as bool, hidden: data['hidden'] as bool, capture: data['capture'] as bool);
    if (!mounted ||
        (result.idle == _autoLockEnabled && result.hidden == _lockWhenHidden && result.capture == previousCapture)) {
      return;
    }
    setState(() => _savingPreferences = true);
    try {
      if (result.capture != previousCapture && !WindowPrivacy.setCaptureAllowed(result.capture)) {
        _notice(t.captureSettingFailed);
        return;
      }
      await _preferences!.save(result.idle, lockWhenHidden: result.hidden, captureAllowed: result.capture);
      if (!mounted) return;
      setState(() {
        _autoLockEnabled = result.idle;
        _lockWhenHidden = result.hidden;
      });
      _idleTimer?.cancel();
      _touchActivity();
    } catch (_) {
      if (result.capture != previousCapture && !WindowPrivacy.setCaptureAllowed(previousCapture)) {
        _notice(t.captureSettingFailed);
        return;
      }
      if (mounted) {
        _notice(t.vaultPreferencesSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _selectVault(String? id) async {
    if (_busy || _editor.active || _renamingVault || _catalog == null || id == _selectedVaultId) return;
    _lock();
    setState(() => _loading = true);
    try {
      await _lifecycle.select(id);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'read';
        });
      }
    }
  }

  Future<void> _showHistory() async {
    if (_busy || _editor.active || _catalog == null) return;
    final epoch = _securityEpoch;
    final project = _lifecycle.project;
    final session = _session;
    late List<({VaultReference vault, File file, DateTime date})> snapshots;
    try {
      snapshots = await _catalog!.history();
      snapshots = snapshots
          .where((snapshot) => project == null ? !snapshot.vault.isProject : snapshot.vault.id == project.vaultId)
          .toList();
    } catch (_) {
      _notice(t.vaultReadFailed);
      return;
    }
    if (!mounted || epoch != _securityEpoch) return;
    final index = await _configuration(
      'choice',
      data: {
        'title': t.vaultHistory,
        'help': t.vaultHistoryHelp,
        'empty': t.vaultHistoryEmpty,
        'items': [
          for (var index = 0; index < snapshots.length; index++)
            {
              'id': index,
              'title': _vaultLabel(snapshots[index].vault),
              'subtitle': snapshots[index].date.toLocal().toString().split('.').first,
            },
        ],
      },
    );
    final selected = index is int && index >= 0 && index < snapshots.length ? snapshots[index].file : null;
    if (selected == null || !mounted || epoch != _securityEpoch) return;
    if (project == null) {
      await _importVault(snapshot: selected);
      return;
    }
    if (session == null ||
        session.isLocked ||
        !await _confirm(t.vaultHistory, t.projectRestoreRevision) ||
        !mounted ||
        epoch != _securityEpoch) {
      return;
    }
    await _operation(() async {
      final bytes = await VaultStore(file: selected).readEncryptedSnapshot();
      if (epoch != _securityEpoch || session.isLocked) return;
      final previous = await session.openRevision(bytes);
      try {
        _resetBrowser();
        _viewers.closeAll();
        _codesWindow.close();
        _sshConnections.revoke();
        await widget.clearClipboard();
        if (epoch != _securityEpoch || session.isLocked) return;
        await _store!.save(session, previous.entries, folders: previous.folders, projects: previous.projects);
      } finally {
        session.closeRevision(previous);
      }
    });
  }

  Future<void> _showConflicts() async {
    final session = _session;
    if (_busy || _editor.active || session == null || session.isLocked) return;
    final epoch = _securityEpoch;
    final variants = session.entries.where((e) => e.conflictOf != null).toList();
    final selectedId = await _configuration(
      'choice',
      data: {
        'title': t.syncReviewConflicts,
        'help': t.syncReviewHelp,
        'empty': t.syncNoConflicts,
        'items': [
          for (final entry in variants)
            {
              'id': entry.id,
              'title': entry.isDeleted ? '${entry.title} · ${t.browserMovedToTrash}' : entry.title,
              'subtitle': t.syncVariant(id: entry.id.substring(0, entry.id.length < 12 ? entry.id.length : 12)),
              'details': [
                if (entry.isFile)
                  {
                    'label': t.vaultEntryTitle,
                    'value': '${entry.attachments.single.name} · ${entry.attachments.single.size} B',
                  }
                else if (entry.isEnvironment)
                  for (final variable in ProjectEnvironment.decode(entry.notes).variables.entries)
                    {'label': variable.key, 'value': variable.value, 'secret': true}
                else ...[
                  {'label': t.vaultUsername, 'value': entry.username},
                  {'label': t.vaultEntryPassword, 'value': entry.password, 'secret': true},
                  {'label': t.vaultNotes, 'value': entry.notes, 'secret': true},
                ],
              ],
            },
        ],
      },
    );
    final selected = variants.where((entry) => entry.id == selectedId).firstOrNull;
    if (selected == null || !mounted || epoch != _securityEpoch || session.isLocked) {
      return;
    }
    if (!await _confirm(t.syncKeepVariant, t.syncKeepVariantQuestion) ||
        !mounted ||
        epoch != _securityEpoch ||
        session.isLocked) {
      return;
    }
    await _persist([
      for (final e in session.entries)
        if (e.id == selected.id) e.withConflict(null) else if (e.conflictOf != selected.conflictOf) e,
    ]);
  }

  Future<void> _deleteVault() async {
    final store = _store;
    if (_busy || _editor.active || _renamingVault || !_exists || store == null) {
      return;
    }
    final epoch = _securityEpoch;
    final id = _selectedVaultId;
    final reference = _vaults.where((vault) => vault.id == id).firstOrNull;
    final name = _session?.name ?? (reference == null ? t.vaultLocal : _vaultLabel(reference));
    if (!await _confirm(
          t.vaultDeleteVault,
          '${t.vaultDeleteVaultQuestion(name: name)}\n\n${t.projectDeleteWorkspaceHelp}',
        ) ||
        !mounted ||
        _busy ||
        epoch != _securityEpoch ||
        store != _store) {
      return;
    }
    _lock();
    await _operation(() async {
      await _lifecycle.deleteSelected();
      if (mounted) {
        setState(() => _loading = false);
        _notice(t.vaultDeleted, kind: DesktopNoticeKind.success);
      }
    });
  }

  String _vaultLabel(VaultReference vault) =>
      _knownVaultNames[vault.id] ??
      (vault.id == 'legacy' ? t.vaultPrimary : t.vaultIdentifier(id: vault.id.substring(0, 8)));

  void _selectEntryFolder(String value) => setState(() => _editor.folderId = value.isEmpty ? null : value);

  void _cancelEntryEditor() => setState(() {
    _clearEditor();
    _error = null;
  });

  void _refreshTreeState() {
    setState(() {});
    _saveTreeState();
  }

  void _startExternalDrag(PointerDownEvent event, VaultEntry entry) {
    if (_busy == false &&
        (entry.isFile || entry.kind == VaultEntryKind.text) &&
        entry.isDeleted == false &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton) {
      _externalDragCandidate = (pointer: event.pointer, origin: event.position, entry: entry);
    }
  }

  String _locationName(VaultSession session, VaultFolder folder) {
    final parent = session.folders.where((item) => item.id == folder.parentId).firstOrNull;
    return parent == null ? folder.name : '${parent.name} / ${folder.name}';
  }

  void _clearEditor() {
    _entryWindowOpen = false;
    _generationRequest++;
    _editor.clear();
  }

  Future<void> _edit([
    VaultEntry? entry,
    String? folderId,
    bool ssh = false,
    bool authenticator = false,
  ]) async {
    final session = _session;
    if (session == null || session.isLocked || _busy) return;
    if (entry?.isEnvironment == true) {
      await _editEnvironment(entry);
      return;
    }
    setState(() {
      _entryWindowOpen = true;
      _error = null;
      _generationRequest++;
      _editor.start(entry: entry, parentId: folderId, ssh: ssh, authenticator: authenticator);
    });
    try {
      if (entry == null && !authenticator) await _generateEntryPassword();
      if (!mounted || session.isLocked || session != _session) return;
      await _configuration(
        'entry',
        data: {
          'fields': _editor.configuration,
          'ssh': _editor.isSsh,
          'totp': _editor.isTotp,
          'delete': entry != null,
          'folders': [
            for (final folder in session.folders) {'id': folder.id, 'name': _locationName(session, folder)},
          ],
        },
        onAction: (method, value) async {
          if (!mounted || session.isLocked || session != _session) return t.vaultWriteFailed;
          if (method == 'generatorLoad') return (await _generatorService.preferences.load()).toJson();
          if (method == 'generatorSave') {
            await _generatorService.preferences.save(GeneratorOptions.fromJson(value));
            return null;
          }
          if (method == 'delete' && entry != null) {
            await _deleteEntry(entry);
            return !session.isLocked && session == _session && !session.entries.any((item) => item.id == entry.id);
          }
          if (method != 'save' || value is! Map) return t.vaultWriteFailed;
          try {
            _editor.applyConfiguration(value);
            await _save();
            return _editor.active ? _errorText : null;
          } on EntryValidationException {
            return t.vaultFormatFailed;
          }
        },
      );
    } finally {
      if (mounted && session == _session) {
        setState(() {
          _entryWindowOpen = false;
          _clearEditor();
        });
      }
    }
  }

  Future<void> _passwordOptions() async {
    if (_busy || !_hasPasswordEditor) return;
    final epoch = _generatorEpoch;
    final value = await GeneratorDialog.show(
      context: context,
      service: _generatorService,
      copy: widget.copySecret,
      actionLabel: t.generatorUseEntry,
    );
    if (value != null) _useGeneratedPassword(value, epoch: epoch);
  }

  Future<void> _generateEntryPassword() async {
    if (_busy || !_hasPasswordEditor || _session == null || _session!.isLocked) return;
    final epoch = _generatorEpoch;
    final request = ++_generationRequest;
    final previous = _editor.password.text;
    try {
      final options = await _generatorService.preferences.load();
      final value = await _generatorService.generate(options);
      if (mounted &&
          epoch == _generatorEpoch &&
          request == _generationRequest &&
          _hasPasswordEditor &&
          _editor.password.text == previous) {
        _useGeneratedPassword(value, epoch: epoch);
      }
    } catch (_) {
      if (mounted && epoch == _generatorEpoch && request == _generationRequest) _notice(t.generatorFailed);
    }
  }

  Future<void> _save() async {
    try {
      await _saveEntry();
    } on MemoryProtectionException {
      if (mounted) setState(() => _error = 'memory-protection');
    }
  }

  Future<void> _saveEntry() async {
    final session = _session;
    if (_busy || session == null) return;
    try {
      final organization = _editor.prepare(session);
      final folderId = _editor.folderId;
      if (await _persist(organization.entries, folders: organization.folders) && mounted) {
        setState(() {
          _collapsedFolders.remove(folderId ?? '');
          _clearEditor();
        });
        if (session.entries.any((entry) => entry.hasTotp && entry.isDeleted == false)) unawaited(_openCodes());
      }
    } on EntryValidationException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  Future<bool> _persist(
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await _lifecycle.save(entries, folders: folders, name: name) == false) return false;
      if (!mounted || _session != session || session.isLocked) return false;
      return true;
    } on VaultConflictException {
      if (mounted && _session == session) setState(() => _error = 'conflict');
    } on VaultFormatException {
      if (mounted && _session == session) setState(() => _error = 'limit');
    } on MemoryProtectionException {
      if (mounted && _session == session) {
        setState(() => _error = 'memory-protection');
      }
    } catch (_) {
      if (mounted && _session == session) setState(() => _error = 'io');
    } finally {
      if (mounted && _session == session) setState(() => _busy = false);
    }
    return false;
  }

  Future<bool> _confirm(String title, String message, {String? actionLabel}) async =>
      await _configuration('confirm', data: {'title': title, 'message': message, 'action': actionLabel ?? title}) ==
      true;
  VaultCollection _collection(VaultSession session) =>
      VaultCollection(entries: session.entries, folders: session.folders);

  Future<void> _favoriteEntry(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || entry.isDeleted) return;
    final collection = _collection(session);
    if (collection.favorite(entry.id, entry.isFavorite == false)) await _persist(collection.entries);
  }

  Future<void> _deleteEntry(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || entry.isDeleted) return;
    if (entry.isEnvironment) await _projectLaunch.stop(_launchId(session, entry));
    if (!mounted || session.isLocked || session != _session) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = entry.id;
    if (session.entries.any((current) => identical(current, entry)) == false) return;
    _deletedEntries[id] = entry.inTrash(timestamp);
    _deletions.start(id, timestamp, DateTime.now());
    if (await _persist(session.entries.where((current) => current.id != id).toList()) == false) {
      if (mounted) {
        setState(() {
          _deletions.remove(id);
          _deletedEntries.remove(id);
        });
      }
      return;
    }
    _viewers.close(id);
    _sshConnections.revoke();
    if (!mounted || _session != session || session.isLocked) return;
    if (_editor.id == id) setState(_clearEditor);
    setState(() => _deletions.start(id, timestamp, DateTime.now()));
    _deletionTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _deletions.expire(DateTime.now());
        _deletedEntries.removeWhere((id, _) => !_deletions.ids.contains(id));
      });
      if (_deletions.ids.isEmpty) {
        _deletionTimer?.cancel();
        _deletionTimer = null;
      }
    });
    await widget.clearClipboard();
  }

  Future<void> _restoreEntry(String id, {VaultSession? expectedSession, int? deletedAt}) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return;
    if (expectedSession != null && expectedSession != session) return;
    final entry = _deletedEntries[id];
    if (entry == null || _deletions.remaining(id, DateTime.now()) == 0) return;
    if (deletedAt != null && entry.deletedAt != deletedAt) return;
    if (session.entries.any((current) => current.id == id)) return;
    final folderExists = session.folders.any((folder) => folder.id == entry.folderId);
    final restored = entry.inTrash(null).inFolder(folderExists ? entry.folderId : null);
    if (await _persist([...session.entries, restored])) {
      if (mounted && _session == session && session.isLocked == false) {
        setState(() {
          _deletions.remove(id);
          _deletedEntries.remove(id);
        });
      }
    }
  }

  Future<void> _purgeEntry(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || entry.isDeleted == false) return;
    if (await _confirm(t.browserDeleteForever, t.browserDeleteForeverHelp(name: entry.title)) == false) return;
    if (!mounted || _session != session || session.isLocked || _busy) return;
    final collection = _collection(session);
    if (identical(collection.find(entry.id), entry) == false) return;
    if (collection.purge(entry.id)) await _persist(collection.entries);
  }

  Future<void> _startRenameVault() async {
    final session = _session;
    if (_busy || session == null) return;
    final name = await _configuration(
      'name',
      data: {
        'title': t.vaultRename,
        'label': t.vaultName,
        'value': _lifecycle.project?.name ?? session.name ?? t.vaultLocal,
      },
    );
    if (name is! String || !mounted || session.isLocked || session != _session) return;
    _renameName.text = name;
    await _renameVault();
  }

  Future<void> _renameVault() async {
    final session = _session;
    if (_busy || session == null) return;
    final name = _renameName.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _renameInvalid = true);
      return;
    }
    if (_lifecycle.project != null) {
      await _operation(() => _lifecycle.renameProject(name));
      if (mounted && _error == null) setState(() => _renamingVault = false);
      return;
    }
    if (await _persist(session.entries, name: name) && mounted) {
      setState(() {
        _renamingVault = false;
        _renameName.clear();
      });
    }
  }

  Future<void> _nameFolder({VaultFolder? folder, String? parentId}) async {
    final session = _session;
    if (_busy || session == null) return;
    if (folder == null && session.folders.length >= VaultCipher.maxFolders) {
      setState(() => _error = 'limit');
      return;
    }
    parentId = folder?.parentId ?? parentId;
    final isSection = parentId == null;
    final name = await _configuration(
      'name',
      data: {
        'title': folder == null
            ? (isSection ? t.vaultNewFolder : t.vaultNewSubfolder)
            : (isSection ? t.vaultRenameFolder : t.vaultRenameSubfolder),
        'label': isSection ? t.vaultFolderName : t.vaultSubfolderName,
        'value': folder?.name ?? '',
        'existing': session.folders
            .where((f) => f.id != folder?.id && f.parentId == parentId)
            .map((f) => f.name)
            .toList(),
      },
    );
    if (!mounted || name == null || _session != session || session.isLocked) {
      return;
    }
    final changed = folder == null
        ? VaultFolder.create(name, parentId: parentId)
        : VaultFolder(id: folder.id, name: name, parentId: parentId, order: folder.order);
    final folders = [...session.folders];
    final index = folders.indexWhere((f) => f.id == changed.id);
    if (index < 0) {
      folders.add(changed);
    } else {
      folders[index] = changed;
    }
    final organization = VaultOrganization(entries: session.entries, folders: folders);
    if (folder == null) organization.move(VaultItem.folder(changed), parentId);
    if (await _persist(organization.entries, folders: organization.folders) && mounted) {
      setState(() {
        _collapsedFolders.remove(changed.id);
        _collapsedFolders.remove(parentId);
      });
    }
  }

  Future<void> _deleteFolder(VaultFolder folder) async {
    final session = _session;
    if (_busy || session == null) return;
    if (!await _confirm(
          folder.isSection ? t.vaultDeleteFolder : t.vaultDeleteSubfolder,
          folder.isSection
              ? t.vaultDeleteFolderQuestion(name: folder.name)
              : t.vaultDeleteSubfolderQuestion(name: folder.name),
        ) ||
        !mounted ||
        _session != session ||
        session.isLocked) {
      return;
    }
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    organization.deleteFolder(folder);
    if (await _persist(
          organization.entries,
          folders: organization.folders,
        ) &&
        mounted) {
      setState(() {
        _collapsedFolders.remove(folder.id);
        _collapsedFolders.remove('');
      });
    }
  }

  Future<void> _moveItem(
    VaultItem item,
    String? folderId,
    String? beforeKey,
  ) async {
    final session = _session;
    if (_busy ||
        session == null ||
        session.isLocked ||
        (folderId != null && !session.folders.any((f) => f.id == folderId))) {
      return;
    }
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    if (!organization.canMove(item, folderId)) return;
    if (beforeKey != null && organization.children(folderId).every((child) => child.key != beforeKey)) return;
    organization.move(item, folderId, beforeKey: beforeKey);
    if (await _persist(organization.entries, folders: organization.folders) && mounted) {
      setState(() => _collapsedFolders.remove(folderId ?? ''));
    }
  }

  void _lock({
    bool clearClipboard = true,
    bool preserveWorkspace = false,
    bool keepProject = false,
    bool keepNotice = false,
  }) {
    ConfigurationWindows.closeAll();
    _resourcesSession = null;
    _launchProfiles.clear();
    DesktopTooltip.dismissAll();
    DesktopMenuObserver.dismissAll();
    _resetBrowser(keepNotice: keepNotice);
    _sshConnections.revoke();
    if (_sensitiveDialogOpen && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _sensitiveDialogOpen = false;
    }
    _viewers.closeAll();
    _codesWindow.close();
    if (preserveWorkspace) {
      if (keepProject) {
        _lifecycle.lockProject();
      } else {
        _lifecycle.suspendContext();
      }
    } else {
      _lifecycle.lock();
      _projectsMode = false;
      widget.onSectionChanged?.call(false);
    }
    _master.clear();
    _confirmation.clear();
    _vaultName.clear();
    _idleTimer?.cancel();
    _copyNoticeTimer?.cancel();
    _copyNotice = null;
    _treeKey.currentState?.stopDragging();
    if (clearClipboard) unawaited(widget.clearClipboard());
    setState(() {
      _busy = false;
      _loading = false;
      _busyProgress = true;
      _clearEditor();
      _error = null;
      _treeState.clear();
      if (preserveWorkspace) _restoreTreeState();
      _renamingVault = false;
      _renameName.clear();
    });
    if (_store == null) unawaited(_load());
    if (preserveWorkspace) _touchActivity();
  }

  @override
  void dispose() {
    ConfigurationWindows.opened.removeListener(_configurationChanged);
    _projectLaunch.removeListener(_launchChanged);
    _projectLaunch.dispose();
    ConfigurationWindows.closeAll();
    _resourcesSession = null;
    ConfigurationWindows.onActivity = null;
    _cancelPasswordGeneration();
    _fileDrag.dispose();
    _secretDrag.dispose();
    FocusManager.instance.removeListener(_updateSearchHandler);
    widget.onSearchHandlerChanged?.call(null);
    _searchWindow.dispose();
    _browser.clear();
    _deletions.clear();
    _deletedEntries.clear();
    _deletionTimer?.cancel();
    _deletionTimer = null;
    _sshConnections.dispose();
    _copyNoticeTimer?.cancel();
    _copyNotice = null;
    _viewers.closeAll();
    _codesWindow.dispose();
    _lifecycle.lock();
    _systemLock.setMethodCallHandler(null);
    _idleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyActivity);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerActivity);
    _treeKey.currentState?.stopDragging();
    _browserScroll.dispose();
    _formScroll.dispose();
    for (final controller in [
      _master,
      _vaultName,
      _renameName,
      _confirmation,
    ]) {
      controller.clear();
      controller.dispose();
    }
    _editor.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  String get _errorText => switch (_error) {
    'totp-invalid' => t.totpInvalid,
    'ssh-invalid' => t.sshInvalid,
    'required' => t.vaultPasswordRequired,
    'mismatch' => t.vaultPasswordMismatch,
    'password-policy' => t.vaultPasswordRequirements,
    'memory-protection' => t.vaultMemoryProtectionFailed,
    'unlock' => t.vaultUnlockFailed,
    'format' => t.vaultFormatFailed,
    'conflict' => t.vaultConflict,
    'title' => t.vaultTitleRequired,
    'limit' => t.vaultLimit,
    'read' => t.vaultReadFailed,
    _ => t.vaultWriteFailed,
  };

  List<VaultEntry> get _pendingEntries {
    final session = _session;
    if (session == null || session.isLocked) return [];
    final pending = <VaultEntry>[];
    for (final entry in _deletedEntries.values) {
      if (!_deletions.ids.contains(entry.id) || session.entries.any((current) => current.id == entry.id)) continue;
      final folderExists = session.folders.any((folder) => folder.id == entry.folderId);
      pending.add(folderExists ? entry : entry.inFolder(null));
    }
    return pending;
  }

  Future<void> _dragFileOut(VaultEntry entry) async {
    final session = _session;
    if (_busy || session == null || session.isLocked || entry.isDeleted || !entry.isFile) return;
    DesktopTooltip.dismissAll();
    DesktopMenuObserver.dismissAll();
    _touchActivity();
    try {
      await _fileDrag.start(
        attachment: entry.attachments.single,
        allowed: () =>
            mounted &&
            _contentActive &&
            !_busy &&
            _session == session &&
            !session.isLocked &&
            session.entries.contains(entry) &&
            !entry.isDeleted,
      );
    } catch (_) {
      if (mounted && _session == session && !session.isLocked) _notice(t.vaultFileDragFailed);
    }
  }

  Future<void> _dragSecretOut(VaultEntry entry) async {
    final session = _session;
    if (_busy || _fileDrag.active || session == null || session.isLocked || entry.isDeleted) return;
    DesktopTooltip.dismissAll();
    DesktopMenuObserver.dismissAll();
    _touchActivity();
    bool allowed() =>
        mounted &&
        _contentActive &&
        !_busy &&
        _session == session &&
        !session.isLocked &&
        session.entries.contains(entry) &&
        !entry.isDeleted;
    try {
      final result = await _secretDrag.start(
        entry: entry,
        allowed: allowed,
        labels: {
          'hover': t.vaultSecretDragHover,
          'login': t.vaultSecretDragLogin,
          'password': t.vaultSecretDragPassword,
          'pair': t.vaultSecretDragPair,
          'missingLogin': t.vaultSecretDragNoLogin,
          'missingPassword': t.vaultSecretDragNoPassword,
        },
      );
      if (!allowed()) return;
      switch (result) {
        case SecretDragResult.partial:
          _notice(t.vaultSecretDragPartial, kind: DesktopNoticeKind.warning);
        case SecretDragResult.unsupported:
          _notice(t.vaultSecretDragUnsupported);
        case SecretDragResult.targetLost:
          _notice(t.vaultSecretDragTargetLost);
        case SecretDragResult.targetChanged:
          _notice(t.vaultSecretDragTargetChanged);
        case SecretDragResult.missingValue:
          _notice(t.vaultSecretDragMissingValue);
        case SecretDragResult.failed:
          _notice(t.vaultSecretDragFailed);
        case SecretDragResult.filled:
        case SecretDragResult.cancelled:
          break;
      }
    } catch (_) {
      if (allowed()) _notice(t.vaultSecretDragFailed);
    }
  }

  Future<void> _copyEntry(VaultEntry entry) async {
    final session = _session;
    if (session == null || session.isLocked || _busy || entry.isDeleted) return;
    final copied = await widget.copySecret(entry.password);
    if (mounted && copied && _session == session && !session.isLocked) {
      _copyNoticeTimer?.cancel();
      setState(() => _copyNotice = (session: session, entryId: entry.id));
      _copyNoticeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copyNotice = null);
      });
    }
  }

  Future<void> _openCodes() async {
    final session = _session;
    if (!mounted || !_windowShown || _busy || session == null || session.isLocked || _contentActive == false) return;
    try {
      await _codesWindow.open(
        session: TotpSession(
          vault: session,
          isValid: () => mounted && _windowShown && _contentActive && _session == session,
          copy: widget.copySecret,
          clearClipboard: widget.clearClipboard,
          activity: _touchActivity,
        ),
        locale: LocaleSettings.currentLocale.languageCode,
        onBlur: () => widget.onCodesBlur?.call(),
      );
    } catch (_) {
      if (mounted) _notice(t.totpOpenFailed);
    }
  }

  Future<void> _entryMenu(VaultEntry entry, Offset position) async {
    final session = _session;
    if (_busy || session == null || session.isLocked) return;
    final action = await DesktopMenu.show<String>(
      context: context,
      position: position,
      items: entry.isDeleted
          ? [
              InsetMenuItem(value: 'restore', label: t.browserRestore, icon: Icons.restore_rounded),
              InsetMenuItem(
                value: 'purge',
                label: t.browserDeleteForever,
                icon: Icons.delete_forever_outlined,
                destructive: true,
              ),
            ]
          : [
              if (entry.isFile || entry.isSsh || entry.isTotp || entry.hasPassword)
                InsetMenuItem(
                  value: 'use',
                  label: entry.isFile
                      ? t.searchOpenFile
                      : entry.isSsh
                      ? t.sshConnect
                      : entry.isTotp
                      ? t.totpTitle
                      : t.copy,
                  icon: entry.isFile
                      ? Icons.description_outlined
                      : entry.isSsh
                      ? Icons.terminal_rounded
                      : entry.isTotp
                      ? Icons.timer_outlined
                      : Icons.copy_rounded,
                ),
              InsetMenuItem(
                value: 'edit',
                label: entry.isFile ? t.vaultSaveAttachment : t.vaultEditEntry,
                icon: entry.isFile ? Icons.save_alt_rounded : Icons.edit_outlined,
              ),
              InsetMenuItem(
                value: 'favorite',
                label: entry.isFavorite ? t.browserUnfavorite : t.browserFavorite,
                icon: entry.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              ),
              const PopupMenuDivider(),
              InsetMenuItem(
                value: 'delete',
                label: entry.isFile ? t.vaultDeleteFile : t.vaultDeleteEntry,
                icon: Icons.delete_outline_rounded,
                destructive: true,
              ),
            ],
    );
    if (!mounted || _busy || _session != session || session.isLocked || session.entries.contains(entry) == false) {
      return;
    }
    switch (action) {
      case 'restore':
        await _restoreEntry(entry.id);
      case 'purge':
        await _purgeEntry(entry);
      case 'use':
        if (entry.isFile) {
          await _openFile(entry);
        } else if (entry.isSsh) {
          await _connectSsh(entry);
        } else if (entry.isTotp) {
          await _openCodes();
        } else {
          await _copyEntry(entry);
        }
      case 'edit':
        if (entry.isFile) {
          await _extractAttachment(entry.attachments.single);
        } else {
          _edit(entry);
        }
      case 'favorite':
        await _favoriteEntry(entry);
      case 'delete':
        await _deleteEntry(entry);
    }
  }

  String get _heading {
    if (_lifecycle.project case final project?) return project.name;
    if (_session case final session?) return session.name ?? t.vaultLocal;
    return _exists ? t.vaultLocked : t.emptyVault;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onWorkspaceChanged?.call(_lifecycle.workspaceUnlocked);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSearchHandler());
    if (_restoreCodesPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreCodesAfterConfiguration());
      });
    }
    if (_loading && _openingProjectId == null) {
      return const Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(minHeight: 2));
    }
    if (_showingProjects || _openingProjectId != null) {
      return _ProjectsPanel(
        archived: _archivedProjects,
        hasArchived: _lifecycle.projects.any((p) => p.archived),
        onArchiveView: () => setState(() => _archivedProjects = !_archivedProjects),
        projects: _lifecycle.projects.where((p) => p.archived == _archivedProjects).toList(),
        busy: _busy || _loading,
        showProgress: _busyProgress,
        openingId: _openingProjectId,
        onCreate: _createProject,
        onOpen: _openProject,
        onArchive: _restoreArchivedProject,
        onDelete: _deleteProject,
      );
    }
    final session = _session;
    if (session != null && _lifecycle.project != null && !_inlineEditorActive) {
      return _ProjectWorkspace(
        title: _heading,
        session: session,
        selectedId: _environmentId,
        directory: _projectDirectory,
        profiles: _launchProfiles,
        launch: _projectLaunch,
        launchId: (entry) => _launchId(session, entry),
        busy: _busy,
        onSelect: (entry) => setState(() => _environmentId = entry.id),
        showProgress: _busyProgress,
        onCreate: () => _editEnvironment(),
        onEdit: _editEnvironment,
        onConfigure: _configureLaunch,
        onRun: _runEnvironment,
        onStop: (entry) => _projectLaunch.stop(_launchId(session, entry)),
        onDuplicate: (entry) => _editEnvironment(entry, true),
        onImport: _importProjectFolder,
        onSecrets: _openProjectSecrets,
        onRename: _startRenameVault,
        createActions: _VaultCreateActions(
          compact: true,
          busy: _busy,
          onEntry: () => _edit(),
          onSsh: () => _edit(null, null, true),
          onTotp: () => _edit(null, null, false, true),
          onFile: _addFile,
          onTextFile: _createTextFile,
          onSearch: _requestSearch,
        ),
        onBack: () => showSection(true),
        onSettings: _showPreferences,
        onDelete: _deleteEntry,
      );
    }
    final entryPresenter = _VaultEntryPresenter(
      busy: _busy,
      deletions: _deletions,
      onRestoreEntry: _restoreEntry,
      activeSession: _session,
      copyNotice: _copyNotice,
      onOpenCodes: _openCodes,
      onOpenFile: _openFile,
      onConnectSsh: _connectSsh,
      onCopyEntry: _copyEntry,
      onEnvironment: _editEnvironment,
      onFavoriteEntry: _favoriteEntry,
      onEntryMenu: _entryMenu,
      onStartExternalDrag: _startExternalDrag,
    );
    final content = _VaultWorkspace(
      controller: session != null && _inlineEditorActive == false ? _browserScroll : _formScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error == 'read') ...[
            Text(_errorText),
            TextButton(onPressed: _load, child: Text(t.retry)),
          ] else if (session == null) ...[
            if (_projectsMode && _lifecycle.project == null)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(t.projectUnlockWorkspace)),
            if (_lifecycle.project?.unlockWithWorkspace == true)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _open,
                  icon: const Icon(Icons.lock_open_outlined, size: 16),
                  label: Text(t.projectOpen),
                ),
              )
            else
              _VaultUnlockForm(
                exists: _exists,
                busy: _busy,
                vaultName: _vaultName,
                master: _master,
                confirmation: _confirmation,
                onOpen: _open,
              ),
            if (_lifecycle.project != null) ...[
              const SizedBox(height: 12),
              Text(t.projectRestoreHelp, style: const TextStyle(fontSize: 12)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _restoreProject,
                  icon: const Icon(Icons.file_open_outlined, size: 16),
                  label: Text(t.projectRestore),
                ),
              ),
            ],
          ] else if (_inlineEditorActive)
            _VaultEntryEditor(
              draft: _editor,
              busy: _busy,
              isSsh: _editor.isSsh,
              locationSelector: _VaultFolderSelector(
                session: session,
                editor: _editor,
                onLocationName: _locationName,
                busy: _busy,
                onSelectEntryFolder: _selectEntryFolder,
              ),
              onSave: _save,
              onCancel: _cancelEntryEditor,
              onDelete: _editor.id == null
                  ? null
                  : () => _deleteEntry(session.entries.firstWhere((entry) => entry.id == _editor.id)),
              onPasswordOptions: _passwordOptions,
              onGenerate: () => unawaited(_generateEntryPassword()),
            )
          else ...[
            _VaultBrowser(
              pendingEntries: _pendingEntries,
              collapsed: _collapsedFolders,
              onCollapsedChanged: _refreshTreeState,
              session: session,
              tree: _VaultFolderTree(
                session: session,
                treeKey: _treeKey,
                busy: _busy,
                collapsedFolders: _collapsedFolders,
                onSaveTreeState: _saveTreeState,
                deletions: _deletions,
                pendingEntries: _pendingEntries,
                onNameFolder: _nameFolder,
                onDeleteFolder: _deleteFolder,
                onEdit: _edit,
                onAddFile: _addFile,
                onCreateTextFile: _createTextFile,
                onMoveItem: _moveItem,
                entryPresenter: entryPresenter,
              ),
              entryPresenter: entryPresenter,
              pendingIds: _deletions.ids,
            ),
          ],
        ],
      ),
    );
    return SensitiveClipboardScope(
      copy: widget.copySecret,
      child: Listener(
        onPointerDown: (_) => _touchActivity(),
        onPointerHover: (_) => _touchActivity(),
        onPointerSignal: (_) => _touchActivity(),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                child: _VaultHeader(
                  title: _heading,
                  unlocked: session != null,
                  renaming: _renamingVault,
                  renameName: _renameName,
                  busy: _busy,
                  renameInvalid: _renameInvalid,
                  savingPreferences: _savingPreferences,
                  showSettings: _inlineEditorActive == false && _renamingVault == false,
                  switcher: _catalog != null && _inlineEditorActive == false && _renamingVault == false
                      ? _VaultSwitcher(
                          busy: _busy,
                          onShowSection: showSection,
                          onImportVault: _importVault,
                          onDeleteVault: _deleteVault,
                          onShowHistory: _showHistory,
                          onShowConflicts: _showConflicts,
                          onSelectVault: _selectVault,
                          lifecycle: _lifecycle,
                          vaults: _vaults,
                          onVaultLabel: _vaultLabel,
                          selectedVaultId: _selectedVaultId,
                          activeSession: _session,
                          editor: _editor,
                          exists: _exists,
                          renamingVault: _renamingVault,
                        )
                      : null,
                  onRename: _renameVault,
                  onStartRename: _startRenameVault,
                  onCancelRename: () => setState(() {
                    _renamingVault = false;
                    _renameName.clear();
                  }),
                  onSettings: _showPreferences,
                ),
              ),
              if (session != null && _inlineEditorActive == false)
                _VaultCreateActions(
                  busy: _busy,
                  onEntry: () => _edit(),
                  onSsh: () => _edit(null, null, true),
                  onTotp: () => _edit(null, null, false, true),
                  onFile: _addFile,
                  onTextFile: _createTextFile,
                  onSearch: _requestSearch,
                ),
              const Divider(height: 1),
              if (constraints.hasBoundedHeight) Expanded(child: content) else content,
              if (_busy && _busyProgress && !_waitingForPassword) const LinearProgressIndicator(minHeight: 2),
              if (_error != null && _error != 'read')
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                  child: Text(_errorText, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
