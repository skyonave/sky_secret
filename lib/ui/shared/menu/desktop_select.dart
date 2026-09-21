import 'package:flutter/material.dart';

import '../desktop_tooltip.dart';
import 'desktop_menu.dart';
import 'inset_menu_item.dart';

/// The existing inset desktop menu presented as a field.
class DesktopSelect<T> extends StatelessWidget {
  final T value;
  final String? label;
  final List<({T value, String label, IconData icon})> items;
  final ValueChanged<T>? onChanged;
  const DesktopSelect({super.key, required this.value, required this.items, required this.onChanged, this.label});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selected = items.where((item) => item.value == value).firstOrNull;
      return PopupMenuButton<T>(
        enabled: onChanged != null,
        tooltip: '',
        routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
        popUpAnimationStyle: AnimationStyle.noAnimation,
        requestFocus: true,
        onOpened: DesktopTooltip.dismissAll,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        borderRadius: BorderRadius.circular(4),
        constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final item in items)
            InsetMenuItem(value: item.value, label: item.label, icon: item.icon, selected: item.value == value),
        ],
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            enabled: onChanged != null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(selected?.label ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more_rounded, size: 20),
            ],
          ),
        ),
      );
    },
  );
}
