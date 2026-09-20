part of '../vault_panel.dart';

typedef _ProjectDraft = ({String name, String? password});

class _ProjectCreateDialog extends StatefulWidget {
  const _ProjectCreateDialog();

  @override
  State<_ProjectCreateDialog> createState() => _ProjectCreateDialogState();
}

class _ProjectCreateDialogState extends State<_ProjectCreateDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _shared = true;
  String? _error;

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _error = t.vaultNameRequired);
      return;
    }
    if (!_shared && !MasterPasswordPolicy.accepts(_password.text)) {
      setState(() => _error = t.vaultPasswordRequirements);
      return;
    }
    if (!_shared && _password.text != _confirm.text) {
      setState(() => _error = t.vaultPasswordMismatch);
      return;
    }
    final result = (name: name, password: _shared ? null : _password.text);
    _password.clear();
    _confirm.clear();
    Navigator.pop(context, result);
  }

  @override
  void dispose() {
    for (final field in [_name, _password, _confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.projectCreate),
    scrollable: true,
    content: SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _VaultField(controller: _name, label: t.projectName, fieldKey: 'project-name', busy: false),
          DesktopOption(
            title: t.projectShared,
            description: t.projectSharedHelp,
            value: _shared,
            onChanged: (value) => setState(() {
              _shared = value;
              _password.clear();
              _confirm.clear();
              _error = null;
            }),
          ),
          if (!_shared) ...[
            const SizedBox(height: 12),
            Text(t.vaultPasswordRequirements, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            _VaultField(
              controller: _password,
              label: t.vaultMasterPassword,
              fieldKey: 'project-password',
              secret: true,
              busy: false,
            ),
            _VaultField(
              controller: _confirm,
              label: t.vaultConfirmPassword,
              fieldKey: 'project-confirm',
              secret: true,
              busy: false,
              onSubmit: _submit,
            ),
          ],
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
      FilledButton(onPressed: _submit, child: Text(t.projectCreate)),
    ],
  );
}
