part of '../vault_panel.dart';

class _VaultEntryPresenter {
  final VaultDeletionController deletions;
  final bool busy;
  final Future<void> Function(String, {int? deletedAt, VaultSession? expectedSession}) onRestoreEntry;
  final VaultSession? activeSession;
  final ({String entryId, VaultSession session})? copyNotice;
  final Future<void> Function() onOpenCodes;
  final Future<void> Function(VaultEntry) onOpenFile;
  final Future<void> Function(VaultEntry) onConnectSsh;
  final Future<void> Function(VaultEntry) onCopyEntry;
  final Future<void> Function(VaultEntry) onFavoriteEntry;
  final Future<void> Function(VaultEntry, Offset) onEntryMenu;
  final void Function(PointerDownEvent, VaultEntry) onStartExternalDrag;
  const _VaultEntryPresenter({
    required this.deletions,
    required this.busy,
    required this.onRestoreEntry,
    required this.activeSession,
    required this.copyNotice,
    required this.onOpenCodes,
    required this.onOpenFile,
    required this.onConnectSsh,
    required this.onCopyEntry,
    required this.onFavoriteEntry,
    required this.onEntryMenu,
    required this.onStartExternalDrag,
  });

  int remaining(VaultEntry entry) => deletions.remaining(entry.id, DateTime.now());

  bool isCopied(VaultEntry entry) => copyNotice == (session: activeSession, entryId: entry.id);

  bool canUse(VaultEntry entry) =>
      busy == false && entry.isDeleted == false && (entry.isTotp || entry.isFile || entry.isSsh || entry.hasPassword);

  Future<void> use(VaultEntry entry) async {
    if (canUse(entry) == false) return;
    if (entry.isTotp) {
      await onOpenCodes();
    } else if (entry.isFile) {
      await onOpenFile(entry);
    } else if (entry.isSsh) {
      await onConnectSsh(entry);
    } else {
      await onCopyEntry(entry);
    }
  }

  Future<void> undoDeletion(VaultEntry entry) async {
    if (busy || remaining(entry) == 0) return;
    await onRestoreEntry(entry.id, expectedSession: activeSession, deletedAt: deletions.timestamp(entry.id));
  }
}
