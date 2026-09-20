part of '../vault_panel.dart';

class _VaultEntryTarget extends StatelessWidget {
  final _VaultTreeController controller;

  final VaultItem item;
  final String? nextKey;

  final _VaultEntryPresenter entryPresenter;

  const _VaultEntryTarget({
    required this.controller,
    required this.item,
    required this.nextKey,
    required this.entryPresenter,
  });

  @override
  Widget build(BuildContext context) {
    void hover(DragTargetDetails<_VaultDrag> details) {
      if (details.data.item.key == item.key || !controller._accept(details.data, item.parentId)) return;
      final box = controller._entryKeys[item.key]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final pointer = box.globalToLocal(details.offset + controller._grabOffset);
        final before = pointer.dy < box.size.height / 2 ? item.key : nextKey;
        controller._hoverInsertion(_VaultInsertion(item.parentId, before), details);
      }
    }

    return DragTarget<_VaultDrag>(
      key: controller._entryKeys.putIfAbsent(item.key, GlobalKey.new),
      onWillAcceptWithDetails: (details) {
        if (details.data.item.key == item.key || !controller._accept(details.data, item.parentId)) return false;
        hover(details);
        return true;
      },
      onMove: hover,
      onAcceptWithDetails: (details) => controller._dropInsertion(details.data),
      builder: (context, candidates, rejected) => _VaultDraggable(
        controller: controller,
        item: item,
        child: _VaultEntryItem(entry: item.entry!, entryPresenter: entryPresenter),
      ),
    );
  }
}
