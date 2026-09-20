part of '../vault_panel.dart';

class _VaultFolderSelector extends StatelessWidget {
  final VaultSession session;
  final VaultEntryController editor;
  final String Function(VaultSession, VaultFolder) onLocationName;
  final bool busy;
  final void Function(String) onSelectEntryFolder;

  const _VaultFolderSelector({
    required this.session,
    required this.editor,
    required this.onLocationName,
    required this.busy,
    required this.onSelectEntryFolder,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selectedName = session.folders
          .where((folder) => folder.id == editor.folderId)
          .map((folder) => onLocationName(session, folder))
          .firstOrNull;
      return DesktopTooltip(
        message: t.vaultLocation,
        child: PopupMenuButton<String>(
          key: ValueKey('entry-folder-${editor.id ?? 'new'}'),
          enabled: !busy,
          tooltip: '',
          routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
          popUpAnimationStyle: AnimationStyle.noAnimation,
          requestFocus: true,
          onOpened: DesktopTooltip.dismissAll,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          borderRadius: BorderRadius.circular(4),
          constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
          onSelected: onSelectEntryFolder,
          itemBuilder: (context) => [
            InsetMenuItem(
              value: '',
              label: t.vaultRoot,
              icon: Icons.folder_outlined,
              selected: editor.folderId == null,
            ),
            for (final folder in session.folders)
              InsetMenuItem(
                value: folder.id,
                label: onLocationName(session, folder),
                icon: Icons.folder_outlined,
                selected: editor.folderId == folder.id,
              ),
          ],
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: t.vaultLocation,
              enabled: !busy,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedName ?? t.vaultRoot,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more_rounded, size: 20),
              ],
            ),
          ),
        ),
      );
    },
  );
}
