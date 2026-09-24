part of '../vault_panel.dart';

class VaultConfigurationForms extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> data;
  final Future<dynamic> Function(String, dynamic) action;
  const VaultConfigurationForms({super.key, required this.kind, required this.data, required this.action});

  @override
  Widget build(BuildContext context) => switch (kind) {
    'preferences' => _VaultPreferencesDialog(
      autoLockEnabled: data['idle'] as bool,
      lockWhenHidden: data['hidden'] as bool,
      captureAllowed: data['capture'] as bool,
      canManageVault: data['manage'] as bool,
      busy: false,
      onExport: () => unawaited(action('export', null)),
      onChangePassword: () => unawaited(action('password', null)),
    ),
    'confirm' => Builder(
      builder: (context) => ConfigurationPage(
        title: Text(data['title'] as String),
        content: SelectableText(data['message'] as String),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(data['action'] as String)),
        ],
      ),
    ),
    'entry' => _EntryConfigurationDialog(data: data, action: action),
    'choice' => _ConfigurationChoiceDialog(data: data, action: action),
    'shortcuts' => ShortcutDialog(desktop: ConfigurationShortcuts(data, action)),
    'github' => GitHubDialog(
      action: action,
      initial: Map<String, dynamic>.from(data['snapshot'] as Map),
      restoreSeparately: data['separately'] == true,
      restore: (_, _) async => false,
      linkExisting: data['link'] == true ? (remote) async => await action('link', remote.id) == true : null,
    ),
    'generator' => GeneratorDialog(
      service: GeneratorService(ConfigurationGeneratorPreferences(action)),
      copy: (value) async => await action('copy', value) == true,
      actionLabel: data['label'] as String,
      canApply: data['apply'] == true,
    ),
    'password' => VaultPasswordDialog(change: data['change'] == true),
    'name' => VaultNameDialog(
      title: data['title'] as String,
      label: data['label'] as String,
      initialValue: data['value'] as String? ?? '',
      existingNames: (data['existing'] as List? ?? []).cast<String>(),
    ),
    'text' => _VaultTextFileDialog(create: (name) async => await action('create', name) as String?),
    _ => throw const FormatException('Unknown configuration'),
  };

  static dynamic encode(String kind, dynamic value) {
    if (value == null) return null;
    if (kind == 'preferences' && value is String) return {'action': value};
    return switch (kind) {
      'preferences' => {'idle': value.idle, 'hidden': value.hidden, 'capture': value.capture},
      'password' => {'current': value.current, 'password': value.password},
      _ => value,
    };
  }
}
