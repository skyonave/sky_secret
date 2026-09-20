import '../shared/desktop_tooltip.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/crypto/crypto.dart';
import '../../core/desktop/desktop_actions.dart';
import '../../core/desktop/clipboard/services/sensitive_clipboard.dart';
import '../../core/desktop/clipboard/services/sensitive_clipboard_boundary.dart';
import '../../core/desktop/clipboard/controllers/sensitive_clipboard_controller.dart';
import '../../core/settings/repositories/vault_preferences.dart';
import '../../core/os/windows/services/windows_sensitive_clipboard.dart';
import '../../core/sync/github/controllers/github_backup.dart';
import '../../i18n/translations.g.dart';
import '../github/github_dialog.dart';
import '../shared/app_theme.dart';
import '../shared/notifications/desktop_notice.dart';

import '../generator/services/generator_service.dart';
import '../../core/settings/repositories/generator_preferences.dart';
import '../shared/menu/desktop_menu.dart';
import '../shared/files/native_file_drop_target.dart';
import '../shared/input/sensitive_text_editing.dart';
import '../vault/vault_panel.dart';
import '../../core/desktop/configuration/controllers/configuration_windows.dart';
part 'widgets/_manager_file_drop_target.dart';
part 'widgets/_manager_title_bar.dart';
part 'widgets/_manager_section_button.dart';
part 'widgets/_git_hub_status.dart';
part 'widgets/_manager_sync_button.dart';
part 'widgets/_manager_footer.dart';

class ManagerWindow extends StatefulWidget {
  final DesktopActions desktop;
  final SensitiveClipboard? clipboard;
  final SensitiveClipboardBoundary? clipboardBoundary;
  final VaultStore? vaultStore;
  final VaultCatalog? vaultCatalog;
  final VaultPreferences? vaultPreferences;
  final GitHubBackup? githubBackup;

  const ManagerWindow({
    super.key,
    required this.desktop,
    this.clipboard,
    this.clipboardBoundary,
    this.vaultStore,
    this.vaultCatalog,
    this.vaultPreferences,
    this.githubBackup,
  });

  @override
  State<ManagerWindow> createState() => _ManagerWindowState();
}

class _ManagerWindowState extends State<ManagerWindow> {
  final _vaultKey = GlobalKey<VaultPanelState>();
  bool _fileHover = false;
  bool _projectsSelected = false;
  bool _projectsAvailable = false;
  late final _generatorService = GeneratorService(
    widget.vaultStore == null ? GeneratorPreferences.local() : GeneratorPreferences(),
  );
  bool _copying = false;

  late final _clipboard = SensitiveClipboardController(
    clipboard: widget.clipboard ?? WindowsSensitiveClipboard(),
    onCleared: () {},
  );
  void _beforeHide() {
    DesktopTooltip.dismissAll();
    DesktopMenuObserver.dismissAll();
    _clipboard.cancelPendingWrites();
    _vaultKey.currentState?.onWindowHidden();
  }

  void _afterShow() => _vaultKey.currentState?.onWindowShown();

  @override
  void initState() {
    super.initState();
    ConfigurationWindows.copy = _copySecret;
    ConfigurationWindows.clearClipboard = _clearVaultClipboard;
    ConfigurationWindows.onBlur = widget.desktop.onCompanionBlur;
    widget.clipboardBoundary?.attach(_copySecret);
    widget.desktop.onBeforeHide = _beforeHide;
    widget.desktop.onAfterShow = _afterShow;
  }

  @override
  void didUpdateWidget(ManagerWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clipboardBoundary != widget.clipboardBoundary) {
      oldWidget.clipboardBoundary?.detach(_copySecret);
      widget.clipboardBoundary?.attach(_copySecret);
    }
    if (oldWidget.desktop != widget.desktop) {
      oldWidget.desktop.onBeforeHide = null;
      oldWidget.desktop.onAfterShow = null;
      widget.desktop.onBeforeHide = _beforeHide;
      widget.desktop.onAfterShow = _afterShow;
    }
  }

  void _setFileHover(bool hovering) {
    if (!hovering) _vaultKey.currentState?.updateFileDropPosition(null);
    widget.desktop.setFileDragHover(hovering);
    if (!mounted || _fileHover == hovering) return;
    _fileHover = hovering;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _receiveFiles(List<String> paths) async {
    final vault = _vaultKey.currentState;
    final token = vault?.fileDropSession;
    final folderId = vault?.fileDropFolderId;
    _setFileHover(false);
    if (vault == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    try {
      if (!await widget.desktop.focusFileDrop() || !mounted) return;

      await vault.importDroppedFiles(paths, sessionToken: token, folderId: folderId);
    } catch (_) {
      if (mounted) {
        DesktopNoticeHost.show(context, t.vaultDropReadFailed);
      }
    }
  }

  Future<bool> _copySecret(String value) async {
    if (_copying) return false;
    setState(() => _copying = true);
    try {
      if (await _clipboard.write(value) == false) return false;

      return true;
    } on ClipboardUnavailable {
      if (mounted) {
        DesktopNoticeHost.show(context, t.clipboardBusy);
      }
      return false;
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _clearVaultClipboard() => _clipboard.clear();

  @override
  void dispose() {
    ConfigurationWindows.closeAll();
    ConfigurationWindows.copy = null;
    ConfigurationWindows.clearClipboard = null;
    ConfigurationWindows.onBlur = null;
    widget.clipboardBoundary?.detach(_copySecret);
    widget.desktop.onBeforeHide = null;
    widget.desktop.onAfterShow = null;
    widget.desktop.setFileDragHover(false);
    _clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SensitiveClipboardScope(
    copy: _copySecret,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(widget.desktop.hide()),
      },
      child: Focus(
        autofocus: true,
        child: _ManagerFileDropTarget(
          onSetFileHover: _setFileHover,
          canAcceptFiles: _vaultKey.currentState?.canAcceptFileDrop ?? false,
          dropHint: _vaultKey.currentState?.fileDropHint ?? t.vaultDropLocked,
          onPosition: (position) => _vaultKey.currentState?.updateFileDropPosition(position),
          onReceiveFiles: _receiveFiles,
          fileHover: _fileHover,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _ManagerTitleBar(
                    desktop: widget.desktop,
                    onSectionChanged: (projects) => _vaultKey.currentState?.showSection(projects),
                    projectsSelected: _projectsSelected,
                    projectsAvailable: _projectsAvailable,
                  ),
                  Expanded(
                    child: VaultPanel(
                      onSectionChanged: (projects) => setState(() => _projectsSelected = projects),
                      onWorkspaceChanged: (available) {
                        if (_projectsAvailable == available) return;
                        setState(() {
                          _projectsAvailable = available;
                          if (!available) _projectsSelected = false;
                        });
                      },
                      generatorService: _generatorService,
                      onFileDragChanged: widget.desktop.setFileDragActive,
                      onSearchHandlerChanged: widget.desktop.setSearchHandler,
                      searchShortcut: () => widget.desktop.searchShortcut,
                      onCodesBlur: widget.desktop.onCompanionBlur,
                      key: _vaultKey,
                      store: widget.vaultStore,
                      catalog: widget.vaultCatalog,
                      preferences: widget.vaultPreferences,
                      githubBackup: widget.githubBackup,
                      copySecret: _copySecret,
                      clearClipboard: _clearVaultClipboard,
                      onSearchDismissed: widget.desktop.hide,
                      onSshAuthorizationChanged: widget.desktop.setSshAuthenticationPending,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.desktop,
                    builder: (context, _) => Visibility(
                      visible: widget.desktop.notice != null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Text(
                          widget.desktop.notice ?? '',
                          style: const TextStyle(color: Color(0xFFFFCB8A), fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                  _ManagerFooter(
                    githubBackup: widget.githubBackup,
                    footerButtonStyle: _footerButtonStyle,
                    onShowGitHub: (backup) => _vaultKey.currentState?.showGitHub(backup),
                    onSync: (backup) async => _vaultKey.currentState?.synchronize(backup),
                    desktop: widget.desktop,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  ButtonStyle get _footerButtonStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    foregroundColor: AppColors.muted,
    textStyle: const TextStyle(fontSize: 11),
  );
}
