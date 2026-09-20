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
  late final _variables = [
    for (final item in (widget.data['variables'] as Map? ?? {}).entries)
      _EnvironmentFields(item.key as String, item.value as String),
  ];
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    try {
      final name = _name.text.trim();
      if (name.isEmpty || name.length > 120) throw const FormatException();
      final variables = <String, String>{};
      final names = <String>{};
      for (final fields in _variables) {
        final key = fields.name.text.trim();
        if (!names.add(key.toUpperCase())) throw const FormatException();
        variables[key] = fields.value.text;
      }
      final environment = ProjectEnvironment(variables);
      setState(() => _saving = true);
      final error = await widget.save({'name': name, 'contents': environment.encode()});
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = error);
    } on FormatException {
      setState(() => _error = t.projectVariablesInvalid);
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
    for (final fields in _variables) {
      fields.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _saving,
    child: ConfigurationPage(
      title: Text(t.projectEnvironmentEdit),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VaultField(controller: _name, label: t.projectEnvironmentName, fieldKey: 'environment-name', busy: false),
          Text(t.projectVariablesProtected, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          for (final fields in _variables)
            Padding(
              key: ObjectKey(fields),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _VaultField(
                          controller: fields.name,
                          label: t.projectVariableName,
                          fieldKey: 'variable-name',
                          busy: false,
                        ),
                        _VaultField(
                          controller: fields.value,
                          label: t.projectVariableValue,
                          fieldKey: 'variable-value',
                          secret: true,
                          busy: false,
                        ),
                      ],
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
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _variables.length >= 128
                  ? null
                  : () => setState(() => _variables.add(_EnvironmentFields('', ''))),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(t.projectVariableAdd),
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
