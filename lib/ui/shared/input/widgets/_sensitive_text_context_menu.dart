part of '../sensitive_text_editing.dart';

class _SensitiveTextContextMenu extends StatelessWidget {
  final EditableTextState state;
  final Future<void> Function({required bool cut}) onTransfer;

  const _SensitiveTextContextMenu({required this.state, required this.onTransfer});

  @override
  Widget build(BuildContext context) {
    final items = SensitiveTextActions.menuItems(
      original: state.contextMenuButtonItems,
      transfer: onTransfer,
      hideToolbar: state.hideToolbar,
    );
    return AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: items);
  }
}
