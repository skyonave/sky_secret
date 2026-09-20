part of '../vault_panel.dart';

class _ProjectsPanel extends StatelessWidget {
  final List<VaultProject> projects;
  final bool busy;
  final VoidCallback onCreate;
  final ValueChanged<VaultProject> onOpen;
  final ValueChanged<VaultProject> onArchive;
  final VoidCallback onLock;
  final bool archived;
  final VoidCallback onArchiveView;

  const _ProjectsPanel({
    required this.projects,
    required this.busy,
    required this.onCreate,
    required this.onOpen,
    required this.onArchive,
    required this.onLock,
    required this.archived,
    required this.onArchiveView,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                archived ? t.projectArchive : t.projects,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            DesktopIconButton(
              tooltip: archived ? t.projects : t.projectArchive,
              onPressed: busy ? null : onArchiveView,
              icon: Icon(archived ? Icons.folder_outlined : Icons.inventory_2_outlined, size: 18),
            ),
            TextButton.icon(
              onPressed: busy ? null : onCreate,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(t.projectCreate),
            ),
            DesktopIconButton(
              tooltip: t.projectLockWorkspace,
              onPressed: busy ? null : onLock,
              icon: const Icon(Icons.lock_outline_rounded, size: 20),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: projects.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  archived ? t.projectArchiveEmpty : t.projectsEmpty,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: busy ? null : () => onOpen(project),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  project.unlockWithWorkspace ? Icons.folder_outlined : Icons.folder_off_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        project.conflictOf != null
                                            ? t.projectConflict
                                            : project.unlockWithWorkspace
                                            ? t.projectShared
                                            : t.projectSeparate,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right_rounded, size: 18),
                              ],
                            ),
                          ),
                        ),
                        DesktopIconButton(
                          tooltip: project.archived ? t.projectUnarchive : t.projectRemove,
                          onPressed: busy ? null : () => onArchive(project),
                          icon: Icon(project.archived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
    ],
  );
}
