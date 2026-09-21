part of '../vault_panel.dart';

class _EntryConfigurationDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<dynamic> Function(String, dynamic) action;
  const _EntryConfigurationDialog({required this.data, required this.action});

  @override
  State<_EntryConfigurationDialog> createState() => _EntryConfigurationDialogState();
}

class _EntryConfigurationDialogState extends State<_EntryConfigurationDialog> {
  final _draft = VaultEntryController();
  late final _generator = GeneratorService(ConfigurationGeneratorPreferences(widget.action));
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft.start(ssh: widget.data['ssh'] == true, authenticator: widget.data['totp'] == true);
    _draft.applyConfiguration(widget.data['fields'] as Map);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final error = await widget.action('save', _draft.configuration);
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = error as String);
    } catch (_) {
      if (mounted) setState(() => _error = t.vaultWriteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate({bool options = false}) async {
    if (_busy) return;
    try {
      final value = options
          ? await GeneratorDialog.show(
              context: context,
              service: _generator,
              copy: (value) async => await widget.action('copy', value) == true,
              actionLabel: t.generatorUseEntry,
            )
          : await _generator.generate(await _generator.preferences.load());
      if (mounted && value != null) setState(() => _draft.password.text = value);
    } catch (_) {
      if (mounted) setState(() => _error = t.generatorFailed);
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConfigurationPage(
    title: Text(
      _draft.isSsh
          ? t.sshAdd
          : _draft.isTotp
          ? t.totpAdd
          : t.vaultAddEntry,
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VaultEntryEditor(
          draft: _draft,
          busy: _busy,
          isSsh: _draft.isSsh,
          locationSelector: DesktopSelect<String>(
            value: _draft.folderId ?? '',
            label: t.vaultLocation,
            items: [
              (value: '', label: t.vaultRoot, icon: Icons.folder_outlined),
              for (final folder in widget.data['folders'] as List)
                (value: folder['id'] as String, label: folder['name'] as String, icon: Icons.folder_outlined),
            ],
            onChanged: _busy ? null : (value) => setState(() => _draft.folderId = value == '' ? null : value),
          ),
          onSave: _save,
          onCancel: () => Navigator.pop(context),
          onDelete: widget.data['delete'] == true
              ? () async {
                  if (await widget.action('delete', null) == true && context.mounted) Navigator.pop(context);
                }
              : null,
          onPasswordOptions: () => _generate(options: true),
          onGenerate: _generate,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    ),
  );
}
