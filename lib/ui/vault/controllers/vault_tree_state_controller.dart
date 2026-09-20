class VaultTreeStateController {
  final collapsed = <String>{};
  final _saved = <String, Set<String>>{};
  String? _vaultId;

  void restore(String vaultId, Set<String> initial) {
    clear();
    _vaultId = vaultId;
    collapsed.addAll(_saved[vaultId] ?? initial);
  }

  void clear() {
    final vaultId = _vaultId;
    if (vaultId != null) _saved[vaultId] = Set.of(collapsed);
    _vaultId = null;
    collapsed.clear();
  }
}
