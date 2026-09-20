part of '../vault_panel.dart';

class _VaultEntryEditor extends StatelessWidget {
  final VaultEntryController draft;
  final bool busy;
  final bool isSsh;
  final Widget locationSelector;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final VoidCallback onPasswordOptions;
  final VoidCallback onGenerate;

  const _VaultEntryEditor({
    required this.draft,
    required this.busy,
    required this.isSsh,
    required this.locationSelector,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
    required this.onPasswordOptions,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        if (busy == false) onSave();
      },
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: locationSelector,
        ),
        _VaultField(busy: busy, controller: draft.title, label: t.vaultEntryTitle, fieldKey: 'entry-title'),
        if (isSsh) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _VaultField(busy: busy, controller: draft.sshHost, label: t.sshHost, fieldKey: 'ssh-host'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VaultField(busy: busy, controller: draft.sshPort, label: t.sshPort, fieldKey: 'ssh-port'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t.sshHelp, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
        if (draft.isTotp == false) ...[
          _VaultField(busy: busy, controller: draft.username, label: t.vaultUsername, fieldKey: 'entry-username'),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: draft.password,
            builder: (context, value, _) => _VaultField(
              busy: busy,
              controller: draft.password,
              label: t.vaultPasswordLength(length: value.text.characters.length),
              fieldKey: 'entry-password',
              secret: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('entry-password-options'),
                  onPressed: busy ? null : onPasswordOptions,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(t.generatorOpen),
                ),
                OutlinedButton.icon(
                  key: const Key('generate-entry-password'),
                  onPressed: busy ? null : onGenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(t.generatorAgain),
                ),
              ],
            ),
          ),
          _VaultField(busy: busy, controller: draft.notes, label: t.vaultNotes, fieldKey: 'entry-notes', lines: 3),
        ],
        if (draft.isTotp) ...[
          _VaultField(busy: busy, controller: draft.totp, label: t.totpSecret, fieldKey: 'entry-totp', secret: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t.totpSetupHelp, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
        Row(
          children: [
            TextButton(
              onPressed: busy ? null : onCancel,
              child: Text(t.cancel),
            ),
            if (onDelete != null)
              DesktopIconButton(
                tooltip: t.vaultDeleteEntry,
                key: const Key('delete-editing-entry'),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            const Spacer(),
            DesktopTooltip(
              message: '${t.save} · Ctrl+S',
              child: FilledButton(
                key: const Key('save-entry'),
                onPressed: busy ? null : onSave,
                child: Text(busy ? t.saving : t.save),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
