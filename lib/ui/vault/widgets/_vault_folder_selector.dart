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
  Widget build(BuildContext context) => DesktopSelect<String>(
    key: ValueKey('entry-folder-${editor.id ?? 'new'}'),
    value: editor.folderId ?? '',
    label: t.vaultLocation,
    items: [
      (value: '', label: t.vaultRoot, icon: Icons.folder_outlined),
      for (final folder in session.folders)
        (value: folder.id, label: onLocationName(session, folder), icon: Icons.folder_outlined),
    ],
    onChanged: busy ? null : onSelectEntryFolder,
  );
}
