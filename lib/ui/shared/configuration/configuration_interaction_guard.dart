import 'package:flutter/material.dart';

import '../../../core/desktop/configuration/controllers/configuration_windows.dart';
import '../../../i18n/translations.g.dart';

class ConfigurationInteractionGuard extends StatefulWidget {
  final Widget child;
  const ConfigurationInteractionGuard({super.key, required this.child});

  @override
  State<ConfigurationInteractionGuard> createState() => _ConfigurationInteractionGuardState();
}

class _ConfigurationInteractionGuardState extends State<ConfigurationInteractionGuard> {
  final _barrierFocus = FocusNode();
  FocusNode? _previousFocus;

  @override
  void initState() {
    super.initState();
    ConfigurationWindows.opened.addListener(_changed);
  }

  void _changed() {
    final open = ConfigurationWindows.opened.value;
    if (open) _previousFocus = FocusManager.instance.primaryFocus;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ConfigurationWindows.opened.value != open) return;
      if (open) {
        _barrierFocus.requestFocus();
      } else {
        final previous = _previousFocus;
        _previousFocus = null;
        if (previous != null && previous.context != null && previous.canRequestFocus) previous.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    ConfigurationWindows.opened.removeListener(_changed);
    _barrierFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = ConfigurationWindows.opened.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: open,
          child: ExcludeSemantics(
            excluding: open,
            child: AbsorbPointer(absorbing: open, child: widget.child),
          ),
        ),
        if (open)
          Positioned.fill(
            child: Focus(
              focusNode: _barrierFocus,
              onKeyEvent: (_, _) => KeyEventResult.handled,
              child: AbsorbPointer(
                child: Material(
                  color: const Color(0xB30B131B),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        t.configurationInteractionBlocked,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
