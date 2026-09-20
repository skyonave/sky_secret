part of '../vault_panel.dart';

class _VaultFolderNode extends StatelessWidget {
  final _VaultTreeController controller;

  final VaultFolder folder;

  final Future<void> Function(Offset, VaultFolder?) onContextMenu;

  final _VaultEntryPresenter entryPresenter;

  const _VaultFolderNode({
    required this.controller,
    required this.folder,
    required this.onContextMenu,
    required this.entryPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final expanded = !controller.collapsed.contains(folder.id);
    final header = GestureDetector(
      key: controller._headerKeys.putIfAbsent(folder.id, GlobalKey.new),
      onSecondaryTapUp: (details) => onContextMenu(details.globalPosition, folder),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('folder-header-${folder.id}'),
                onTap: controller.busy ? null : () => controller._toggleFolder(folder),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 20),
                      const SizedBox(width: 4),
                      Icon(folder.isSection ? Icons.segment_rounded : Icons.folder_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      Text(
                        '${controller._organization.children(folder.id).length}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: ValueKey('node-${folder.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VaultDropTarget(
          controller: controller,
          parentId: folder.id,
          child: _VaultDraggable(controller: controller, item: VaultItem.folder(folder), child: header),
        ),
        if (expanded)
          Container(
            margin: const EdgeInsets.only(left: 12, bottom: 6),
            padding: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: _VaultTreeChildren(
              controller: controller,
              parentId: folder.id,
              onContextMenu: onContextMenu,
              entryPresenter: entryPresenter,
            ),
          ),
      ],
    );
  }
}
