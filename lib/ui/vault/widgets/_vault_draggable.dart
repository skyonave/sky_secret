part of '../vault_panel.dart';

class _VaultDraggable extends StatelessWidget {
  final _VaultTreeController controller;

  final VaultItem item;
  final Widget child;

  const _VaultDraggable({required this.controller, required this.item, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Draggable<_VaultDrag>(
      key: ValueKey('drag-${item.key}'),
      data: _VaultDrag(controller.session, item),
      maxSimultaneousDrags: controller.busy || controller.filtering || controller.pendingIds.contains(item.entry?.id)
          ? 0
          : 1,
      dragAnchorStrategy: controller._dragAnchor,
      onDragUpdate: (details) => controller._scroll(details.globalPosition),
      onDragEnd: (_) {
        controller._finishDrag();
      },
      onDragCompleted: controller._finishDrag,
      onDraggableCanceled: (_, _) => controller._finishDrag(),
      feedback: Builder(
        builder: (context) => SizedBox(
          width: constraints.maxWidth,
          height: controller._dragHeight,
          child: _VaultDragPreview(item: item),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: child),
      child: child,
    ),
  );
}
