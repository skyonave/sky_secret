part of '../vault_panel.dart';

class _ConfigurationChoiceDialog extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<dynamic> Function(String, dynamic) action;
  const _ConfigurationChoiceDialog({required this.data, required this.action});

  @override
  Widget build(BuildContext context) => ConfigurationPage(
    title: Text(data['title'] as String),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(data['help'] as String),
        const SizedBox(height: 12),
        if ((data['items'] as List).isEmpty) Text(data['empty'] as String),
        for (final item in (data['items'] as List).cast<Map>()) _ConfigurationChoiceItem(item: item, action: action),
      ],
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.githubClose))],
  );
}

class _ConfigurationChoiceItem extends StatefulWidget {
  final Map item;
  final Future<dynamic> Function(String, dynamic) action;
  const _ConfigurationChoiceItem({required this.item, required this.action});

  @override
  State<_ConfigurationChoiceItem> createState() => _ConfigurationChoiceItemState();
}

class _ConfigurationChoiceItemState extends State<_ConfigurationChoiceItem> {
  final _revealed = <int>{};

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final details = (item['details'] as List? ?? []).cast<Map>();
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: details.isEmpty
          ? ListTile(
              contentPadding: const EdgeInsets.all(12),
              shape: shape,
              title: Text(item['title'] as String),
              subtitle: Text(item['subtitle'] as String),
              trailing: const Icon(Icons.restore_rounded),
              onTap: () => Navigator.pop(context, item['id']),
            )
          : ExpansionTile(
              shape: shape,
              collapsedShape: shape,
              tilePadding: const EdgeInsets.all(12),
              childrenPadding: const EdgeInsets.all(12),
              title: Text(item['title'] as String),
              subtitle: Text(item['subtitle'] as String),
              children: [
                for (var index = 0; index < details.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(details[index]['label'] as String, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 6),
                        SelectableText(
                          details[index]['secret'] == true && !_revealed.contains(index)
                              ? '••••••••'
                              : details[index]['value'] as String,
                        ),
                        if (details[index]['secret'] == true)
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () => setState(() {
                                  if (!_revealed.add(index)) _revealed.remove(index);
                                }),
                                icon: const Icon(Icons.visibility_outlined, size: 16),
                                label: Text(t.syncShowPassword),
                              ),
                              TextButton.icon(
                                onPressed: () => widget.action('copy', details[index]['value']),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: Text(t.copy),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                FilledButton.tonal(onPressed: () => Navigator.pop(context, item['id']), child: Text(t.syncKeepVariant)),
              ],
            ),
    );
  }
}
