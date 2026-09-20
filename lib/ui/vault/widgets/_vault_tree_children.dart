part of '../vault_panel.dart';

class _VaultTreeChildren extends StatelessWidget {
  final _VaultTreeController controller;

  final String? parentId;

  final Future<void> Function(Offset, VaultFolder?) onContextMenu;

  final _VaultEntryPresenter entryPresenter;

  const _VaultTreeChildren({
    required this.controller,
    required this.parentId,
    required this.onContextMenu,
    required this.entryPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final items = controller._organization.children(parentId);
    return Column(
      key: ValueKey('children-$parentId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _VaultDropTarget(
            controller: controller,
            parentId: parentId,
            beforeKey: items[index].key,
            insertion: true,
            child: const SizedBox.shrink(),
          ),
          if (items[index].folder case final folder?)
            _VaultFolderNode(
              controller: controller,
              folder: folder,
              onContextMenu: onContextMenu,
              entryPresenter: entryPresenter,
            )
          else
            _VaultEntryTarget(
              controller: controller,
              item: items[index],
              nextKey: index + 1 < items.length ? items[index + 1].key : null,
              entryPresenter: entryPresenter,
            ),
        ],
        _VaultDropTarget(
          controller: controller,
          parentId: parentId,
          insertion: items.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              parentId == null ? t.vaultRootDropHint : t.vaultFolderDropHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
