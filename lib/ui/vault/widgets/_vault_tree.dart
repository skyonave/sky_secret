part of '../vault_panel.dart';

class _VaultTree extends StatefulWidget {
  final VaultSession session;
  final bool busy;
  final Set<String> pendingIds;
  final List<VaultEntry> pendingEntries;
  final Set<String> collapsed;
  final VoidCallback onCollapsedChanged;
  final _VaultEntryPresenter entryPresenter;
  final void Function(String?) createFolder;
  final void Function(VaultFolder) renameFolder;
  final void Function(VaultFolder) deleteFolder;
  final void Function(String?) addEntry;
  final void Function(String?) addFile;
  final void Function(String?) addSsh;
  final void Function(String?) addTotp;
  final void Function(String?) createTextFile;
  final Future<void> Function(VaultItem, String?, String?) move;

  const _VaultTree({
    super.key,
    required this.session,
    required this.busy,
    required this.pendingIds,
    required this.pendingEntries,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.entryPresenter,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
    required this.addEntry,
    required this.addFile,
    required this.addSsh,
    required this.addTotp,
    required this.createTextFile,
    required this.move,
  });

  @override
  State<_VaultTree> createState() => _VaultTreeState();
}

class _VaultTreeState extends State<_VaultTree> {
  late final _controller = _VaultTreeController(
    session: widget.session,
    busy: widget.busy,
    pendingIds: widget.pendingIds,
    pendingEntries: widget.pendingEntries,
    collapsed: widget.collapsed,
    onCollapsedChanged: widget.onCollapsedChanged,
    move: widget.move,
    scrollable: () => Scrollable.of(context),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void didUpdateWidget(_VaultTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.configure(
      session: widget.session,
      busy: widget.busy,
      pendingIds: widget.pendingIds,
      pendingEntries: widget.pendingEntries,
      collapsed: widget.collapsed,
      onCollapsedChanged: widget.onCollapsedChanged,
      move: widget.move,
    );
  }

  String? get nativeFolderId => _controller.nativeFolderId;
  void nativeHover(Offset? position) => _controller.nativeHover(position);
  void stopDragging() => _controller.stopDragging();

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  List<PopupMenuEntry<String>> _menu(VaultFolder? folder) => [
    InsetMenuItem(value: 'entry', label: t.vaultAddEntry, icon: Icons.add_rounded),
    InsetMenuItem(value: 'ssh', label: t.sshAdd, icon: Icons.terminal_rounded),
    InsetMenuItem(value: 'totp', label: t.totpAdd, icon: Icons.timer_outlined),
    InsetMenuItem(value: 'file', label: t.vaultAddFile, icon: Icons.upload_file_outlined),
    InsetMenuItem(value: 'text', label: t.vaultCreateTextFile, icon: Icons.note_add_outlined),
    if (folder == null || folder.isSection)
      InsetMenuItem(
        value: 'folder',
        label: folder == null ? t.vaultNewFolder : t.vaultNewSubfolder,
        icon: Icons.create_new_folder_outlined,
      ),
    if (folder != null) ...[
      InsetMenuItem(
        value: 'rename',
        label: folder.isSection ? t.vaultRenameFolder : t.vaultRenameSubfolder,
        icon: Icons.edit_outlined,
      ),
      InsetMenuItem(
        value: 'delete',
        label: folder.isSection ? t.vaultDeleteFolder : t.vaultDeleteSubfolder,
        icon: Icons.delete_outline_rounded,
      ),
    ],
  ];

  void _action(String action, VaultFolder? folder) {
    if (widget.busy || widget.session.isLocked) return;
    switch (action) {
      case 'entry':
        widget.addEntry(folder?.id);
      case 'ssh':
        widget.addSsh(folder?.id);
      case 'totp':
        widget.addTotp(folder?.id);
      case 'file':
        widget.addFile(folder?.id);
      case 'text':
        widget.createTextFile(folder?.id);
      case 'folder':
        widget.createFolder(folder?.id);
      case 'rename':
        if (folder != null) widget.renameFolder(folder);
      case 'delete':
        if (folder != null) widget.deleteFolder(folder);
    }
  }

  Future<void> _contextMenu(Offset position, VaultFolder? folder) async {
    if (widget.busy || widget.session.isLocked) return;
    final session = widget.session;
    final action = await DesktopMenu.show<String>(
      context: context,
      position: position,
      items: _menu(folder),
    );
    if (mounted && identical(session, widget.session) && action != null) _action(action, folder);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _VaultDropTarget(
        controller: _controller,
        parentId: null,
        child: GestureDetector(
          onSecondaryTapUp: (details) => _contextMenu(details.globalPosition, null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DesktopTooltip(
                    message: t.vaultMoveToRoot,
                    child: Text(t.vaultContents, style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                DesktopIconButton(
                  key: const Key('add-folder'),
                  tooltip: t.vaultNewFolder,
                  padding: const EdgeInsets.all(7),
                  onPressed: widget.busy ? null : () => widget.createFolder(null),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                ),
              ],
            ),
          ),
        ),
      ),
      _VaultTreeChildren(
        controller: _controller,
        parentId: null,
        onContextMenu: _contextMenu,
        entryPresenter: widget.entryPresenter,
      ),
    ],
  );
}

class _VaultDragPreview extends StatelessWidget {
  final VaultItem item;

  const _VaultDragPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.entry case final entry?) {
      return _VaultEntryCard(entry: entry, lifted: true);
    }
    final colors = Theme.of(context).colorScheme;
    final icon = item.folder == null
        ? (item.entry!.isFile ? Icons.insert_drive_file_outlined : Icons.key_outlined)
        : (item.folder!.isSection ? Icons.segment_rounded : Icons.folder_outlined);
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
