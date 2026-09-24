part of '../vault_panel.dart';

class _VaultSwitcher extends StatelessWidget {
  final bool busy;
  final Future<void> Function({File? snapshot}) onImportVault;
  final Future<void> Function() onDeleteVault;
  final Future<void> Function() onShowHistory;
  final Future<void> Function() onShowConflicts;
  final Future<void> Function(String?) onSelectVault;
  final List<VaultReference> vaults;
  final String Function(VaultReference) onVaultLabel;
  final String? selectedVaultId;
  final VaultSession? activeSession;
  final VaultEntryController editor;
  final bool exists;
  final bool renamingVault;

  const _VaultSwitcher({
    required this.busy,
    required this.onImportVault,
    required this.onDeleteVault,
    required this.onShowHistory,
    required this.onShowConflicts,
    required this.onSelectVault,
    required this.vaults,
    required this.onVaultLabel,
    required this.selectedVaultId,
    required this.activeSession,
    required this.editor,
    required this.exists,
    required this.renamingVault,
  });

  @override
  Widget build(BuildContext context) => DesktopTooltip(
    message: t.vaultChoose,
    child: PopupMenuButton<String>(
      key: const Key('vault-switcher'),
      tooltip: '',
      routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      requestFocus: true,
      onOpened: DesktopTooltip.dismissAll,
      enabled: !busy,
      icon: const Icon(Icons.expand_more_rounded, size: 21),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      onSelected: (id) => switch (id) {
        'import' => onImportVault(),
        'delete' => onDeleteVault(),
        'history' => onShowHistory(),
        'conflicts' => onShowConflicts(),
        _ => onSelectVault(id == 'new' ? null : id),
      },
      itemBuilder: (_) => [
        for (final vault in vaults)
          InsetMenuItem(
            value: vault.id,
            label: onVaultLabel(vault),
            icon: vault.id == selectedVaultId ? Icons.check_rounded : Icons.lock_outline_rounded,
            selected: vault.id == selectedVaultId,
          ),
        const PopupMenuDivider(),
        InsetMenuItem(
          key: const Key('new-vault'),
          value: 'new',
          label: t.vaultNew,
          icon: Icons.add_rounded,
        ),
        InsetMenuItem(
          value: 'import',
          label: t.vaultImport,
          icon: Icons.file_open_outlined,
        ),
        InsetMenuItem(
          value: 'history',
          label: t.vaultHistory,
          icon: Icons.history_rounded,
        ),
        if (activeSession != null && !editor.active)
          InsetMenuItem(
            value: 'conflicts',
            label: t.syncReviewConflicts,
            icon: Icons.difference_outlined,
          ),
        if (exists && !editor.active && !renamingVault) ...[
          const PopupMenuDivider(),
          InsetMenuItem(
            key: const Key('delete-vault'),
            value: 'delete',
            label: t.vaultDeleteVault,
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
        ],
      ],
    ),
  );
}
