class VaultSearchSession {
  final bool Function() isValid;
  final void Function(String) onQueryChanged;
  final void Function() activity;
  bool _closed = false;

  VaultSearchSession({required this.isValid, required this.onQueryChanged, required this.activity});

  bool get valid => !_closed && isValid();

  bool search(String query) {
    if (!valid || query.length > 256) return false;
    activity();
    onQueryChanged(query);
    return true;
  }

  void close() {
    _closed = true;
  }
}
