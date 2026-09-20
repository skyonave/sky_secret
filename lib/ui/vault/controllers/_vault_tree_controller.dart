part of '../vault_panel.dart';

class _VaultTreeController extends ChangeNotifier {
  VaultSession session;
  bool busy;
  Set<String> pendingIds;
  List<VaultEntry> pendingEntries;
  Set<String> collapsed;
  VoidCallback onCollapsedChanged;
  Future<void> Function(VaultItem, String?, String?) move;
  final ScrollableState Function() scrollable;
  bool _disposed = false;

  _VaultTreeController({
    required this.session,
    required this.busy,
    required this.pendingIds,
    required this.pendingEntries,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.move,
    required this.scrollable,
  });

  void configure({
    required VaultSession session,
    required bool busy,
    required Set<String> pendingIds,
    required List<VaultEntry> pendingEntries,
    required Set<String> collapsed,
    required VoidCallback onCollapsedChanged,
    required Future<void> Function(VaultItem, String?, String?) move,
  }) {
    if (this.session != session || busy || session.isLocked) {
      stopDragging();
      _nativeFolderId = null;
      _nativeHover = false;
      _insertion = null;
      _insertionPointer = null;
    }
    this.session = session;
    this.busy = busy;
    this.pendingIds = pendingIds;
    this.pendingEntries = pendingEntries;
    this.collapsed = collapsed;
    this.onCollapsedChanged = onCollapsedChanged;
    this.move = move;
  }

  void _update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  Timer? _expandTimer;
  String? _expandId;
  EdgeDraggingAutoScroller? _scroller;
  final _headerKeys = <String, GlobalKey>{};
  String? _nativeFolderId;
  bool _nativeHover = false;
  final _gapKeys = <({String? parentId, String? beforeKey}), GlobalKey>{};
  final _entryKeys = <String, GlobalKey>{};
  _VaultInsertion? _insertion;
  Offset _grabOffset = Offset.zero;
  Offset? _insertionPointer;
  double _dragHeight = 56;

  VaultOrganization get _organization => VaultOrganization(
    entries: [...session.entries, ...pendingEntries]
        .where(
          (entry) => (entry.isDeleted == false || pendingIds.contains(entry.id)) && entry.isFavorite == false,
        )
        .toList(),
    folders: session.folders,
  );

  void stopDragging() {
    _expandTimer?.cancel();
    _expandId = null;
    _scroller?.stopAutoScroll();
  }

  @override
  void dispose() {
    _disposed = true;
    stopDragging();
    super.dispose();
  }

  void _hoverFolder(String? id) {
    if (id == _expandId) return;
    _expandTimer?.cancel();
    _expandId = id;
    if (id == null || !collapsed.contains(id)) return;
    _expandTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_disposed && !busy && !session.isLocked) {
        _update(() => collapsed.remove(id));
        onCollapsedChanged();
      }
    });
  }

  void _scroll(Offset position) {
    _scroller ??= EdgeDraggingAutoScroller(scrollable(), velocityScalar: 12);
    _scroller!.startAutoScrollIfNecessary(Rect.fromCenter(center: position, width: 1, height: 1));
  }

  String? get nativeFolderId => _nativeFolderId;

  void nativeHover(Offset? position) {
    String? folderId;
    if (position != null && !busy && !session.isLocked) {
      for (final folder in session.folders) {
        final box = _headerKeys[folder.id]?.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize && (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
          folderId = folder.id;
          break;
        }
      }
      _scroll(position);
    } else {
      stopDragging();
    }
    _hoverFolder(folderId);
    if (_nativeFolderId != folderId || _nativeHover != (position != null)) {
      _update(() {
        _nativeFolderId = folderId;
        _nativeHover = position != null;
      });
    }
  }

  bool _accept(_VaultDrag drag, String? parentId) =>
      !busy && !session.isLocked && identical(drag.session, session) && _organization.canMove(drag.item, parentId);

  void _hoverInsertion(_VaultInsertion insertion, DragTargetDetails<_VaultDrag> details) {
    if (!_accept(details.data, insertion.parentId) || insertion.beforeKey == details.data.item.key) return;
    if (_insertion?.key == insertion.key) return;
    final pointer = details.offset + _grabOffset;
    if (_keepInsertion(details)) return;
    _hoverFolder(null);
    _update(() {
      _insertion = insertion;
      _insertionPointer = pointer;
    });
  }

  bool _keepInsertion(DragTargetDetails<_VaultDrag> details) {
    if (_insertion == null) return false;
    final pointer = details.offset + _grabOffset;
    final gap = _gapKeys[_insertion!.key]?.currentContext?.findRenderObject();
    if (gap is RenderBox && gap.hasSize) {
      final bounds = (gap.localToGlobal(Offset.zero) & gap.size).inflate(6);
      if (bounds.contains(pointer)) return true;
    }
    return _insertionPointer != null && (pointer - _insertionPointer!).distance < 8;
  }

  void _hoverDestination(String? parentId, DragTargetDetails<_VaultDrag> details) {
    if (!_accept(details.data, parentId)) return;
    if (_keepInsertion(details)) return;
    _clearInsertion();
    _hoverFolder(parentId);
  }

  void _clearInsertion() {
    if (_insertion == null) return;
    _update(() {
      _insertion = null;
      _insertionPointer = null;
    });
  }

  void _dropInsertion(_VaultDrag drag) {
    final insertion = _insertion;
    if (insertion != null && _accept(drag, insertion.parentId)) {
      unawaited(move(drag.item, insertion.parentId, insertion.beforeKey));
    }
    _finishDrag();
  }

  Offset _dragAnchor(Draggable<Object> draggable, BuildContext context, Offset position) {
    _grabOffset = childDragAnchorStrategy(draggable, context, position);
    _dragHeight = context.size!.height;
    return _grabOffset;
  }

  void _toggleFolder(VaultFolder folder) {
    _update(() {
      if (collapsed.contains(folder.id)) {
        collapsed.remove(folder.id);
      } else {
        collapsed.add(folder.id);
      }
      onCollapsedChanged();
    });
  }

  void _finishDrag() {
    stopDragging();
    if (!_disposed) _clearInsertion();
  }
}
