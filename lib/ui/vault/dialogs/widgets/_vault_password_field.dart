part of '../vault_password_dialog.dart';

class _VaultPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final void Function() onSubmit;

  const _VaultPasswordField({
    required this.controller,
    required this.label,
    required this.fieldKey,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SensitiveTextEditing(
      controller: controller,
      enabled: true,
      readOnly: false,
      obscureText: true,
      builder: (context, menuBuilder) => TextField(
        contextMenuBuilder: menuBuilder,
        enableIMEPersonalizedLearning: false,
        key: Key(fieldKey),
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 1048576,
        decoration: InputDecoration(labelText: label, counterText: ''),
        onSubmitted: (_) => onSubmit(),
      ),
    ),
  );
}
