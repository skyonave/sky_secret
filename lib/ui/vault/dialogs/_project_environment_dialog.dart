part of '../vault_panel.dart';

class _ProjectEnvironmentDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<String?> Function(Map<String, dynamic>) save;
  const _ProjectEnvironmentDialog({required this.data, required this.save});

  @override
  State<_ProjectEnvironmentDialog> createState() => _ProjectEnvironmentDialogState();
}

class _ProjectEnvironmentDialogState extends State<_ProjectEnvironmentDialog> {
  late final _name = TextEditingController(text: widget.data['name'] as String? ?? '');
  final _source = TextEditingController();
  late final _variables = [
    for (final item in (widget.data['variables'] as Map? ?? {}).entries)
      _EnvironmentFields(item.key as String, item.value as String),
  ];
  String? _error;
  bool _saving = false;
  bool _textMode = false;
  bool _revealed = false;

  ProjectEnvironment _environment() {
    if (_textMode) return ProjectDotenv.parse(_source.text);
    final values = <String, String>{};
    final names = <String>{};
    for (final fields in _variables) {
      final key = fields.name.text.trim();
      if (!names.add(key.toUpperCase())) throw const FormatException();
      values[key] = fields.value.text;
    }
    return ProjectEnvironment(values);
  }

  void _toggleMode() {
    try {
      final value = _environment();
      if (_textMode) {
        final replacement = [for (final item in value.variables.entries) _EnvironmentFields(item.key, item.value)];
        for (final fields in _variables) {
          fields.dispose();
        }
        _variables
          ..clear()
          ..addAll(replacement);
        _source.clear();
      } else {
        _source.text = ProjectDotenv.format(value);
      }
      setState(() {
        _textMode = !_textMode;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(
        () =>
            _error = error.source is int ? t.projectEnvLineError(line: error.source as int) : t.projectVariablesInvalid,
      );
    }
  }

  Future<void> _copy() async {
    try {
      await SensitiveClipboardScope.copyText(context, ProjectDotenv.format(_environment()));
    } on FormatException {
      setState(() => _error = t.projectVariablesInvalid);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    try {
      final name = _name.text.trim();
      if (name.isEmpty || name.length > 120) throw const FormatException();
      final environment = _environment();
      setState(() => _saving = true);
      final error = await widget.save({'name': name, 'contents': environment.encode()});
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = error);
    } on FormatException catch (error) {
      setState(
        () =>
            _error = error.source is int ? t.projectEnvLineError(line: error.source as int) : t.projectVariablesInvalid,
      );
    } catch (_) {
      if (mounted) setState(() => _error = t.vaultWriteFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.clear();
    _name.dispose();
    _source.clear();
    _source.dispose();
    for (final fields in _variables) {
      fields.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _saving,
    child: ConfigurationPage(
      title: Text(widget.data['creating'] == true ? t.projectEnvironmentAdd : t.projectEnvironmentEdit),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VaultField(controller: _name, label: t.projectEnvironmentName, fieldKey: 'environment-name', busy: false),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _toggleMode,
                icon: Icon(_textMode ? Icons.table_rows_outlined : Icons.code, size: 16),
                label: Text(_textMode ? t.projectEnvRows : t.projectEnvText),
              ),
              TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(t.projectEnvCopy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_textMode) ...[
            Text(t.projectEnvTextHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            _VaultField(controller: _source, label: '.env', fieldKey: 'environment-source', busy: false, lines: 14),
          ] else ...[
            Row(
              children: [
                Expanded(child: Text(t.projectVariablesProtected, style: Theme.of(context).textTheme.bodySmall)),
                DesktopIconButton(
                  tooltip: t.projectEnvReveal,
                  onPressed: () => setState(() => _revealed = !_revealed),
                  icon: Icon(_revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final fields in _variables)
              Row(
                key: ObjectKey(fields),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _VaultField(
                      controller: fields.name,
                      label: t.projectVariableName,
                      fieldKey: 'variable-name',
                      busy: false,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.fromLTRB(6, 10, 6, 0), child: Text('=')),
                  Expanded(
                    flex: 3,
                    child: _VaultField(
                      controller: fields.value,
                      label: t.projectVariableValue,
                      fieldKey: 'variable-value',
                      secret: !_revealed,
                      busy: false,
                    ),
                  ),
                  const SizedBox(width: 6),
                  DesktopIconButton(
                    tooltip: t.projectVariableRemove,
                    onPressed: () => setState(() {
                      _variables.remove(fields);
                      fields.dispose();
                    }),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ],
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _variables.length >= 128
                      ? null
                      : () => setState(() => _variables.add(_EnvironmentFields('', ''))),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(t.projectVariableAdd),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    for (final fields in _variables) {
                      fields.value.clear();
                    }
                  }),
                  child: Text(t.projectEnvClearValues),
                ),
              ],
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _save, child: Text(t.save)),
      ],
    ),
  );
}

class _EnvironmentFields {
  final TextEditingController name;
  final TextEditingController value;
  _EnvironmentFields(String name, String value)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);
  void dispose() {
    name.clear();
    value.clear();
    name.dispose();
    value.dispose();
  }
}
