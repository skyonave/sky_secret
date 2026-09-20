part of '../vault_panel.dart';

class _ProjectWorkspace extends StatelessWidget {
  final String title;
  final VaultSession session;
  final String? selectedId;
  final Map<String, ProjectLaunchProfile> profiles;
  final ProjectLaunchController launch;
  final String Function(VaultEntry) launchId;
  final bool busy;
  final ValueChanged<VaultEntry> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<VaultEntry> onEdit;
  final ValueChanged<VaultEntry> onConfigure;
  final ValueChanged<VaultEntry> onRun;
  final ValueChanged<VaultEntry> onStop;
  final ValueChanged<VaultEntry> onDelete;
  final VoidCallback onResources;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onLock;

  const _ProjectWorkspace({
    required this.title,
    required this.session,
    required this.selectedId,
    required this.profiles,
    required this.launch,
    required this.launchId,
    required this.busy,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onConfigure,
    required this.onRun,
    required this.onStop,
    required this.onDelete,
    required this.onResources,
    required this.onBack,
    required this.onSettings,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    final environments = session.entries.where((entry) => entry.isEnvironment && !entry.isDeleted).toList();
    final selected = environments.where((entry) => entry.id == selectedId).firstOrNull ?? environments.firstOrNull;
    final profile = selected == null ? null : profiles[selected.id];
    final id = selected == null ? '' : launchId(selected);
    final running = launch.running(id);
    final starting = launch.starting(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              DesktopIconButton(
                tooltip: t.projects,
                onPressed: busy ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              DesktopIconButton(
                tooltip: t.vaultSettings,
                onPressed: busy ? null : onSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
              ),
              DesktopIconButton(
                tooltip: t.projectLockWorkspace,
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Text(t.projectWorkflow, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(t.projectWorkflowHelp, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(t.projectEnvironments, style: Theme.of(context).textTheme.labelLarge)),
                  TextButton.icon(
                    onPressed: busy ? null : onCreate,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(t.projectEnvironmentAdd),
                  ),
                ],
              ),
              if (selected == null)
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.projectEnvironmentEmpty)),
              if (selected != null) ...[
                DropdownButtonFormField<String>(
                  initialValue: selected.id,
                  key: ValueKey(selected.id),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.projectEnvironments,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    for (final entry in environments)
                      DropdownMenuItem(
                        value: entry.id,
                        child: Text(entry.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) onSelect(environments.firstWhere((entry) => entry.id == value));
                        },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected.conflictOf == null ? t.projectVariablesProtected : t.projectConflict,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    DesktopIconButton(
                      tooltip: t.projectEnvironmentEdit,
                      onPressed: busy || running || starting ? null : () => onEdit(selected),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                    ),
                    DesktopIconButton(
                      tooltip: t.vaultDeleteEntry,
                      onPressed: busy || running || starting ? null : () => onDelete(selected),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    ),
                  ],
                ),
                for (final name in ProjectEnvironment.decode(selected.notes).variables.keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('••••••••', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                Text(
                  profile == null ? t.projectLaunchMissing : t.projectLaunchReady,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (profile != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile.executable,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.directory,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy || running || starting ? null : () => onConfigure(selected),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(t.projectLaunchConfigure),
                    ),
                    FilledButton.icon(
                      onPressed: busy || starting || (!running && (selected.conflictOf != null || profile == null))
                          ? null
                          : () => running ? onStop(selected) : onRun(selected),
                      icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                      label: Text(running ? t.projectStop : t.projectLaunch),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  starting
                      ? t.projectStarting
                      : running
                      ? t.projectRunning
                      : launch.exitCode(id) == null
                      ? t.projectStopped
                      : t.projectExited(code: launch.exitCode(id)!),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : onResources,
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: Text(t.projectResources),
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
