part of '../vault_panel.dart';

class _ProjectImportDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<dynamic> Function(String, dynamic) action;
  const _ProjectImportDialog({required this.data, required this.action});
  @override
  State<_ProjectImportDialog> createState() => _ProjectImportDialogState();
}

class _ProjectImportDialogState extends State<_ProjectImportDialog> {
  late final _files = (widget.data['files'] as List).cast<Map>();
  late final _selected = {
    for (var i = 0; i < _files.length; i++)
      if (_files[i]['invalid'] != true) i,
  };
  bool _saved = false;
  final _imported = <int>{};
  bool _busy = false;
  String? _message;
  Future<void> _run(String method) async {
    setState(() => _busy = true);
    try {
      final result = await widget.action(method, _selected.toList());
      if (!mounted) return;
      if (result == true) {
        if (method == 'import') {
          setState(() {
            _saved = true;
            _imported.addAll(_selected);
            _message = t.projectEnvImported;
          });
        } else {
          Navigator.pop(context);
        }
      } else {
        setState(() => _message = result is String ? result : t.vaultWriteFailed);
      }
    } catch (_) {
      if (mounted) setState(() => _message = t.vaultWriteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConfigurationPage(
    title: Text(t.projectEnvImportFolder),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_saved ? t.projectEnvDeleteHelp : t.projectEnvImportHelp),
        const SizedBox(height: 12),
        for (var index = 0; index < _files.length; index++)
          DesktopOption(
            title: _files[index]['name'] as String,
            description: _files[index]['invalid'] == true
                ? t.projectVariablesInvalid
                : t.projectEnvVariableCount(count: _files[index]['count'] as int),
            value: _selected.contains(index),
            onChanged: _busy || (_saved && !_imported.contains(index)) || _files[index]['invalid'] == true
                ? null
                : (value) => setState(() {
                    if (value) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  }),
          ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(_saved ? t.projectEnvKeepFiles : t.cancel),
      ),
      if (!_saved)
        FilledButton(
          onPressed: _busy || _selected.isEmpty ? null : () => _run('import'),
          child: Text(t.projectEnvImport),
        ),
      if (_saved)
        OutlinedButton(
          onPressed: _busy || _selected.isEmpty ? null : () => _run('remove'),
          child: Text(t.projectEnvDeleteSources),
        ),
    ],
  );
}
