part of '../vault_panel.dart';

class _VaultFolderTree extends StatelessWidget {
  final _VaultEntryPresenter entryPresenter;

  final VaultSession session;
  final GlobalKey<_VaultTreeState> treeKey;
  final bool busy;
  final Set<String> collapsedFolders;
  final void Function() onSaveTreeState;
  final VaultDeletionController deletions;
  final List<VaultEntry> pendingEntries;
  final Future<void> Function({VaultFolder? folder, String? parentId}) onNameFolder;
  final Future<void> Function(VaultFolder) onDeleteFolder;
  final void Function([VaultEntry?, String?, bool, bool]) onEdit;
  final Future<void> Function([String?]) onAddFile;
  final Future<void> Function([String?]) onCreateTextFile;
  final Future<void> Function(VaultItem, String?, String?) onMoveItem;

  const _VaultFolderTree({
    required this.session,
    required this.treeKey,
    required this.busy,
    required this.collapsedFolders,
    required this.onSaveTreeState,
    required this.deletions,
    required this.pendingEntries,
    required this.onNameFolder,
    required this.onDeleteFolder,
    required this.onEdit,
    required this.onAddFile,
    required this.onCreateTextFile,
    required this.onMoveItem,
    required this.entryPresenter,
  });

  @override
  Widget build(BuildContext context) => _VaultTree(
    key: treeKey,
    session: session,
    busy: busy,
    collapsed: collapsedFolders,
    onCollapsedChanged: onSaveTreeState,
    entryPresenter: entryPresenter,
    pendingIds: deletions.ids,
    pendingEntries: pendingEntries,
    createFolder: (parentId) => onNameFolder(parentId: parentId),
    renameFolder: (folder) => onNameFolder(folder: folder),
    deleteFolder: onDeleteFolder,
    addEntry: (parentId) => onEdit(null, parentId),
    addFile: onAddFile,
    addSsh: (parentId) => onEdit(null, parentId, true),
    addTotp: (parentId) => onEdit(null, parentId, false, true),
    createTextFile: onCreateTextFile,
    move: onMoveItem,
  );
}
