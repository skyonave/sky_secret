part of '../vault_panel.dart';

class _ProjectLaunchDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<String?> Function(Map<String, dynamic>) save;
  const _ProjectLaunchDialog({required this.data, required this.save});

  @override
  State<_ProjectLaunchDialog> createState() => _ProjectLaunchDialogState();
}

class _ProjectLaunchDialogState extends State<_ProjectLaunchDialog> {
  late final _executable = TextEditingController(text: widget.data['executable'] as String? ?? '');
  late final _directory = TextEditingController(text: widget.data['directory'] as String? ?? '');
  late final _arguments = TextEditingController(text: (widget.data['arguments'] as List? ?? []).join('\n'));
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    try {
      final profile = ProjectLaunchProfile(
        executable: _executable.text.trim(),
        directory: _directory.text.trim(),
        arguments: _arguments.text.isEmpty
            ? []
            : _arguments.text.split('\n').map((line) => line.replaceAll('\r', '')).toList(),
      );
      setState(() => _saving = true);
      final error = await widget.save(profile.toJson());
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = error);
    } on FormatException {
      setState(() => _error = t.projectLaunchInvalid);
    } catch (_) {
      if (mounted) setState(() => _error = t.vaultPreferencesSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final field in [_executable, _directory, _arguments]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _saving,
    child: ConfigurationPage(
      title: Text(t.projectLaunchConfigure),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.projectLaunchLocal, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _VaultField(controller: _executable, label: t.projectExecutable, fieldKey: 'launch-executable', busy: false),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final file = await openFile(
                  acceptedTypeGroups: [
                    const XTypeGroup(label: 'EXE', extensions: ['exe']),
                  ],
                );
                if (mounted && file != null) _executable.text = file.path;
              },
              child: Text(t.projectBrowse),
            ),
          ),
          _VaultField(controller: _directory, label: t.projectDirectory, fieldKey: 'launch-directory', busy: false),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final directory = await getDirectoryPath();
                if (mounted && directory != null) _directory.text = directory;
              },
              child: Text(t.projectBrowse),
            ),
          ),
          _VaultField(
            controller: _arguments,
            label: t.projectArguments,
            fieldKey: 'launch-arguments',
            busy: false,
            lines: 4,
          ),
          Text(t.projectLaunchHelp, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(t.projectLaunchTrust, style: Theme.of(context).textTheme.bodySmall),
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
