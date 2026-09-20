part of '../vault_panel.dart';

class _VaultDropTarget extends StatelessWidget {
  final _VaultTreeController controller;

  final String? parentId;
  final String? beforeKey;
  final Widget child;
  final bool insertion;

  const _VaultDropTarget({
    required this.controller,
    required this.parentId,
    this.beforeKey,
    required this.child,
    this.insertion = false,
  });

  @override
  Widget build(BuildContext context) => DragTarget<_VaultDrag>(
    key: ValueKey((parentId: parentId, beforeKey: beforeKey, insertion: insertion)),
    onWillAcceptWithDetails: (details) {
      final accepted = controller._accept(details.data, parentId) && beforeKey != details.data.item.key;
      if (accepted) {
        if (insertion) {
          controller._hoverInsertion(_VaultInsertion(parentId, beforeKey), details);
        } else {
          controller._hoverDestination(parentId, details);
        }
      }
      return accepted;
    },
    onMove: (details) {
      if (insertion) {
        controller._hoverInsertion(_VaultInsertion(parentId, beforeKey), details);
      } else {
        controller._hoverDestination(parentId, details);
      }
    },
    onLeave: (_) => controller._hoverFolder(null),
    onAcceptWithDetails: (details) {
      if (insertion || controller._keepInsertion(details)) {
        controller._dropInsertion(details.data);
        return;
      }
      if (controller._accept(details.data, parentId)) {
        unawaited(controller.move(details.data.item, parentId, beforeKey));
      }
      controller._finishDrag();
    },
    builder: (context, candidates, rejected) {
      final active =
          (candidates.isNotEmpty && controller._insertion == null) ||
          (!insertion && controller._nativeHover && controller._nativeFolderId == parentId);
      final colors = Theme.of(context).colorScheme;
      if (insertion) {
        final slot = _VaultInsertion(parentId, beforeKey);
        final opened = controller._insertion?.key == slot.key;
        return AnimatedContainer(
          key: controller._gapKeys.putIfAbsent(slot.key, GlobalKey.new),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: opened ? controller._dragHeight + 4 : 4,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: opened ? colors.primary.withValues(alpha: 0.045) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: opened ? colors.primary.withValues(alpha: 0.22) : Colors.transparent),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: active ? colors.primary.withValues(alpha: 0.55) : Colors.transparent),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
