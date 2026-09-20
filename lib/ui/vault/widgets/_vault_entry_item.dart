part of '../vault_panel.dart';

class _VaultEntryItem extends StatelessWidget {
  final _VaultEntryPresenter entryPresenter;

  final VaultEntry entry;

  const _VaultEntryItem({required this.entry, required this.entryPresenter});

  @override
  Widget build(BuildContext context) {
    final seconds = entryPresenter.remaining(entry);
    if (entry.isDeleted && seconds > 0) {
      return _VaultEntryCard(
        key: ValueKey('entry-card-${entry.id}'),
        entry: entry,
        status: t.browserDeleting(seconds: seconds),
        trailing: TextButton.icon(
          key: ValueKey('undo-delete-${entry.id}'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: entryPresenter.busy ? null : () => unawaited(entryPresenter.undoDeletion(entry)),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: Text(t.browserUndo),
        ),
      );
    }
    final card = _VaultEntryCard(
      entry: entry,
      copied: entryPresenter.isCopied(entry),
      key: ValueKey('entry-card-${entry.id}'),
      onTap: entryPresenter.canUse(entry) ? () => unawaited(entryPresenter.use(entry)) : null,
      trailing: entry.isDeleted
          ? const SizedBox(width: 32)
          : DesktopIconButton(
              tooltip: entry.isFavorite ? t.browserUnfavorite : t.browserFavorite,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: const EdgeInsets.all(7),
              onPressed: entryPresenter.busy ? null : () => entryPresenter.onFavoriteEntry(entry),
              icon: Icon(entry.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded, size: 18),
            ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => entryPresenter.onEntryMenu(entry, details.globalPosition),
      child: DesktopTooltip(
        message: entry.isDeleted
            ? t.browserTrashHelp
            : entry.isTotp
            ? t.totpTitle
            : entry.isFile
            ? t.vaultFileHint
            : entry.isSsh
            ? t.sshConnect
            : t.vaultEntryHint,
        child: Listener(
          onPointerDown: (event) => entryPresenter.onStartExternalDrag(event, entry),
          child: card,
        ),
      ),
    );
  }
}
