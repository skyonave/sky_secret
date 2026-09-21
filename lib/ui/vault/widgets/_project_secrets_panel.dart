part of '../vault_panel.dart';

class _ProjectSecretsPanel extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<dynamic> Function(String, dynamic) action;
  const _ProjectSecretsPanel({required this.data, required this.action});
  @override
  State<_ProjectSecretsPanel> createState() => _ProjectSecretsPanelState();
}

class _ProjectSecretsPanelState extends State<_ProjectSecretsPanel> {
  Timer? _timer;
  List<Map> _rows = [];
  bool _busy = true;
  bool _reading = false;
  bool _failed = false;
  String? _snapshot;
  final _revealed = <(String, String), String>{};
  final _revealing = <(String, String), Object>{};
  late String _title = widget.data['title'] as String;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final state = await widget.action('state', null);
      if (!mounted) return;
      if (state is! Map) {
        setState(() {
          _conceal();
          _rows = [];
          _busy = true;
        });
        return;
      }
      setState(() {
        final snapshot = jsonEncode([state['revision'], state['rows']]);
        if (_snapshot != snapshot || state['busy'] == true) _conceal();
        _snapshot = snapshot;
        _title = state['title'] as String? ?? _title;
        _rows = (state['rows'] as List).cast<Map>();
        _busy = state['busy'] == true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _conceal();
          _rows = [];
          _busy = true;
          _failed = true;
        });
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _act(String method, Map row, [String? field, String? key]) async {
    setState(_conceal);
    var ok = false;
    try {
      ok = await widget.action(method, {'id': row['id'], 'field': field, 'key': key}) == true;
    } catch (_) {}
    if (mounted && (method == 'copyField' || method == 'totp')) {
      DesktopNoticeHost.show(
        context,
        ok ? t.projectSecretCopied : t.projectSecretCopyFailed,
        kind: ok ? DesktopNoticeKind.success : DesktopNoticeKind.error,
      );
    }
  }

  void _conceal() {
    _revealed.clear();
    _revealing.clear();
  }

  Future<void> _toggleValue(Map row, String key) async {
    if (_busy) return;
    final id = (row['id'] as String, key);
    if (_revealed.containsKey(id) || _revealing.containsKey(id)) {
      setState(() {
        _revealed.remove(id);
        _revealing.remove(id);
      });
      return;
    }
    final request = Object();
    setState(() => _revealing[id] = request);
    try {
      final value = await widget.action('reveal', {'id': row['id'], 'key': key});
      if (!mounted || _busy || _revealing[id] != request) return;
      setState(() {
        _revealing.remove(id);
        if (value is String) _revealed[id] = value;
      });
    } catch (_) {
      if (mounted && _revealing[id] == request) setState(() => _revealing.remove(id));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conceal();
    _rows = [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      ('environment', t.projectEnvironments),
      ('text', t.projectSecretAccounts),
      ('ssh', 'SSH'),
      ('totp', 'TOTP'),
      ('file', t.projectSecretFiles),
    ];
    return ConfigurationPage(
      title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
      contentPadding: const EdgeInsets.all(12),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(_failed ? t.configurationFailed : t.projectSecretsEmpty),
            ),
          for (final section in sections)
            if (_rows.any((row) => row['kind'] == section.$1)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                child: Text(section.$2, style: Theme.of(context).textTheme.labelLarge),
              ),
              for (final row in _rows.where((row) => row['kind'] == section.$1))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(row['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          DesktopIconButton(
                            tooltip: t.vaultEditEntry,
                            onPressed: _busy ? null : () => _act('edit', row),
                            icon: const Icon(Icons.edit_outlined, size: 17),
                          ),
                          const SizedBox(width: 4),
                          DesktopIconButton(
                            tooltip: t.vaultDeleteEntry,
                            onPressed: _busy ? null : () => _act('delete', row),
                            icon: const Icon(Icons.delete_outline_rounded, size: 17),
                          ),
                        ],
                      ),
                      if (row['kind'] == 'environment') ...[
                        for (final key in row['keys'] as List)
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  child: SingleChildScrollView(
                                    key: ValueKey((row['id'], key, _revealed.containsKey((row['id'], key)))),
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      '$key = ${_revealed[(row['id'], key)] ?? '••••••••'}',
                                      maxLines: 1,
                                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              DesktopIconButton(
                                tooltip:
                                    _revealed.containsKey((row['id'], key)) || _revealing.containsKey((row['id'], key))
                                    ? t.projectEnvHideValue
                                    : t.projectEnvShowValue,
                                onPressed: _busy ? null : () => _toggleValue(row, key as String),
                                icon: Icon(
                                  _revealed.containsKey((row['id'], key)) || _revealing.containsKey((row['id'], key))
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _busy ? null : () => _act('copyField', row, 'env'),
                            child: Text(t.projectEnvCopy),
                          ),
                        ),
                      ] else
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (row['username'] == true)
                              TextButton(
                                onPressed: _busy ? null : () => _act('copyField', row, 'username'),
                                child: Text(t.vaultUsername),
                              ),
                            if (row['password'] == true)
                              TextButton(
                                onPressed: _busy ? null : () => _act('copyField', row, 'password'),
                                child: Text(t.vaultEntryPassword),
                              ),
                            if (row['notes'] == true)
                              TextButton(
                                onPressed: _busy ? null : () => _act('copyField', row, 'notes'),
                                child: Text(t.vaultNotes),
                              ),
                            if (row['totp'] == true)
                              TextButton(onPressed: _busy ? null : () => _act('totp', row), child: Text(t.totpCopy)),
                            if (row['kind'] == 'file' || row['kind'] == 'ssh')
                              TextButton(
                                onPressed: _busy ? null : () => _act('open', row),
                                child: Text(row['kind'] == 'ssh' ? t.sshConnect : t.projectSecretOpenFile),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
