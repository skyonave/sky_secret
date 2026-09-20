import 'package:flutter/material.dart';

import '../../../i18n/translations.g.dart';
import '../desktop_tooltip.dart';

class ConfigurationPage extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  final EdgeInsets? insetPadding;
  final EdgeInsets? titlePadding;
  final EdgeInsets? contentPadding;
  final EdgeInsets? actionsPadding;

  const ConfigurationPage({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = true,
    this.insetPadding,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleSmall!,
                  child: title ?? const SizedBox(),
                ),
              ),
              DesktopIconButton(
                tooltip: t.githubClose,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  padding: contentPadding ?? const EdgeInsets.all(16),
                  child: SizedBox(width: double.infinity, child: content),
                )
              : Padding(padding: contentPadding ?? const EdgeInsets.all(16), child: content),
        ),
        if (actions?.isNotEmpty == true) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions!),
          ),
        ],
      ],
    ),
  );
}
