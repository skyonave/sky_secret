class StartupProgress {
  final Set<String> _pending;
  final void Function(bool) onComplete;
  bool _successful = true;
  bool _completed = false;

  StartupProgress({required Set<String> stages, required this.onComplete}) : _pending = Set.of(stages);

  void finish(String stage, {required bool success}) {
    if (_completed || !_pending.remove(stage)) return;
    _successful = _successful && success;
    if (_pending.isEmpty) {
      _completed = true;
      onComplete(_successful);
    }
  }
}
