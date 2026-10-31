part of '../vault_panel.dart';

class _VaultBrowser extends StatelessWidget {
  final VaultOrganization organization;
  final bool filtering;
  final Set<String> collapsed;
  final VoidCallback onCollapsedChanged;
  final Widget tree;
  final _VaultEntryPresenter entryPresenter;

  const _VaultBrowser({
    required this.organization,
    required this.filtering,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.tree,
    required this.entryPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = organization.entries.where((entry) => entry.isFavorite).toList()
      ..sort((left, right) => left.order.compareTo(right.order));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (favorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: filtering
                  ? null
                  : () {
                      if (collapsed.contains('@favorites')) {
                        collapsed.remove('@favorites');
                      } else {
                        collapsed.add('@favorites');
                      }
                      onCollapsedChanged();
                    },
              child: Row(
                children: [
                  Icon(
                    !filtering && collapsed.contains('@favorites')
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(t.browserFavorites, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (filtering || !collapsed.contains('@favorites'))
            for (final entry in favorites) _VaultEntryItem(entry: entry, entryPresenter: entryPresenter),
          const SizedBox(height: 6),
        ],
        tree,
        if (filtering && organization.entries.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(t.browserNoResults)),
      ],
    );
  }
}
