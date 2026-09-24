import '../../shared/configuration/configuration_page.dart';

import 'package:flutter/material.dart';

import '../../../core/crypto/crypto.dart';
import '../../../i18n/translations.g.dart';
import '../../shared/input/sensitive_text_editing.dart';
part 'widgets/_vault_password_field.dart';

typedef VaultPasswords = ({String current, String password});

class VaultPasswordDialog extends StatefulWidget {
  final bool change;

  const VaultPasswordDialog({
    super.key,
    this.change = false,
  });

  @override
  State<VaultPasswordDialog> createState() => _VaultPasswordDialogState();
}

class _VaultPasswordDialogState extends State<VaultPasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final field in [_current, _password, _confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty || (widget.change && _current.text.isEmpty)) {
      setState(() => _error = t.vaultPasswordRequired);
    } else if (widget.change && _password.text != _confirm.text) {
      setState(() => _error = t.vaultPasswordMismatch);
    } else if (widget.change && !MasterPasswordPolicy.accepts(_password.text)) {
      setState(() => _error = t.vaultPasswordRequirements);
    } else {
      final result = (current: _current.text, password: _password.text);
      for (final field in [_current, _password, _confirm]) {
        field.clear();
      }
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => ConfigurationPage(
    title: Text(
      widget.change ? t.vaultChangePassword : t.vaultImport,
    ),
    scrollable: true,
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.change ? t.vaultChangePasswordHelp : t.vaultImportHelp,
          ),
          if (widget.change) ...[
            const SizedBox(height: 8),
            Text(t.vaultPasswordRequirements),
            const SizedBox(height: 12),
            Text(t.vaultPasswordBackupWarning),
          ],
          if (widget.change)
            _VaultPasswordField(
              controller: _current,
              label: t.vaultCurrentPassword,
              fieldKey: 'current-master',
              onSubmit: _submit,
            ),
          _VaultPasswordField(
            controller: _password,
            label: widget.change ? t.vaultNewPassword : t.vaultMasterPassword,
            fieldKey: 'transfer-master',
            onSubmit: _submit,
          ),
          if (widget.change)
            _VaultPasswordField(
              controller: _confirm,
              label: t.vaultConfirmPassword,
              fieldKey: 'transfer-confirm',
              onSubmit: _submit,
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t.cancel),
      ),
      FilledButton(
        key: const Key('confirm-password-action'),
        onPressed: _submit,
        child: Text(widget.change ? t.save : t.vaultImport),
      ),
    ],
  );
}
