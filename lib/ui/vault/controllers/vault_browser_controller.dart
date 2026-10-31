import '../../../core/crypto/crypto.dart';

enum VaultView { all, favorites, trash }

class VaultSearchResult {
  final VaultEntry entry;
  final List<String> location;

  const VaultSearchResult(this.entry, this.location);
}

class VaultBrowserController {
  String query = '';
  VaultView view = VaultView.all;

  bool get filtering => query.trim().isNotEmpty || view != VaultView.all;

  VaultOrganization filterOrganization(VaultOrganization organization) {
    if (query.trim().isEmpty) return organization;
    final folders = {for (final folder in organization.folders) folder.id: folder};
    final words = _words;
    final entries = organization.entries.where((entry) => _matches(entry, folders, words)).toList();
    final visibleFolders = <String>{};
    for (final entry in entries) {
      if (entry.isFavorite) continue;
      var folderId = entry.folderId;
      while (folderId != null && visibleFolders.add(folderId)) {
        folderId = folders[folderId]?.parentId;
      }
    }
    return VaultOrganization(
      entries: entries,
      folders: organization.folders.where((folder) => visibleFolders.contains(folder.id)).toList(),
    );
  }

  List<String> get _words => query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

  List<String> _location(VaultEntry entry, Map<String, VaultFolder> folders) {
    final folder = folders[entry.folderId];
    final parent = folders[folder?.parentId];
    return [if (parent != null) parent.name, if (folder != null) folder.name];
  }

  bool _matches(VaultEntry entry, Map<String, VaultFolder> folders, List<String> words) {
    final searchable = [
      entry.title,
      entry.username,
      entry.ssh?.host ?? '',
      ..._location(entry, folders),
    ].join(' ').toLowerCase();
    return words.every(searchable.contains);
  }

  List<VaultSearchResult> results(VaultSession session) {
    if (session.isLocked) return [];
    final folders = {for (final folder in session.folders) folder.id: folder};
    final words = _words;
    final found = <VaultSearchResult>[];
    for (final entry in session.entries) {
      if (entry.isDeleted != (view == VaultView.trash)) continue;
      if (view == VaultView.favorites && entry.isFavorite == false) continue;
      if (_matches(entry, folders, words)) found.add(VaultSearchResult(entry, _location(entry, folders)));
    }
    found.sort((left, right) {
      if (view == VaultView.trash) {
        final deleted = right.entry.deletedAt!.compareTo(left.entry.deletedAt!);
        if (deleted != 0) return deleted;
      }
      final order = left.entry.order.compareTo(right.entry.order);
      return order == 0 ? left.entry.id.compareTo(right.entry.id) : order;
    });
    return found;
  }

  void clear() {
    query = '';
    view = VaultView.all;
  }
}
