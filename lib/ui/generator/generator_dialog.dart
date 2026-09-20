import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/generator/models/generator_options.dart';
import '../../i18n/translations.g.dart';
import '../shared/app_theme.dart';
import '../shared/menu/desktop_menu.dart';
import '../shared/desktop_option.dart';
import '../shared/desktop_tooltip.dart';
import '../shared/input/sensitive_text_editing.dart';
import 'services/generator_service.dart';
part 'widgets/_generator_mode_button.dart';
part 'widgets/_generator_preview.dart';
part 'widgets/_generator_count.dart';
part 'widgets/_password_options.dart';
part 'widgets/_phrase_options.dart';
part 'widgets/_generator_warning.dart';

class GeneratorDialog extends StatefulWidget {
  final GeneratorService service;
  final Future<bool> Function(String) copy;
  final String actionLabel;
  final bool canApply;

  const GeneratorDialog({
    super.key,
    required this.service,
    required this.copy,
    required this.actionLabel,
    required this.canApply,
  });

  @override
  State<GeneratorDialog> createState() => _GeneratorDialogState();

  static Future<String?> show({
    required BuildContext context,
    required GeneratorService service,
    required Future<bool> Function(String) copy,
    required String actionLabel,
    bool canApply = true,
  }) {
    DesktopTooltip.dismissAll();
    return showDialog<String>(
      context: context,
      routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => GeneratorDialog(service: service, copy: copy, actionLabel: actionLabel, canApply: canApply),
    );
  }
}

class _GeneratorDialogState extends State<GeneratorDialog> {
  GeneratorOptions _options = const GeneratorOptions();
  final _count = TextEditingController();
  String _value = '';
  String? _error;
  String? _preferencesError;
  bool _loading = true;
  bool _generating = false;
  bool _copying = false;
  bool _copied = false;
  bool _countValid = true;
  int _revision = 0;
  Timer? _copyNotice;

  bool get _phrase => _options.mode == GeneratorMode.passphrase;
  bool get _ready => !_loading && !_generating && _countValid && _options.valid && _value.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _options = await widget.service.preferences.load();
    } catch (_) {
      _preferencesError = t.generatorPreferencesFailed;
    }
    if (!mounted) return;
    _count.text = '${_phrase ? _options.wordCount : _options.length}';
    setState(() => _loading = false);
    await _generate();
  }

  Future<void> _generate() async {
    final revision = ++_revision;
    setState(() {
      _value = '';
      _copied = false;
      _error = null;
      _generating = _countValid && _options.valid;
    });
    if (!_generating) return;
    try {
      final value = await widget.service.generate(_options);
      if (mounted && revision == _revision) setState(() => _value = value);
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = t.generatorFailed);
    } finally {
      if (mounted && revision == _revision) setState(() => _generating = false);
    }
  }

  void _change(GeneratorOptions options) {
    setState(() => _options = options);
    unawaited(_generate());
    if (options.valid && _countValid) unawaited(_save(options));
  }

  Future<void> _save(GeneratorOptions options) async {
    try {
      await widget.service.preferences.save(options);
      if (mounted) setState(() => _preferencesError = null);
    } catch (_) {
      if (mounted) setState(() => _preferencesError = t.generatorPreferencesFailed);
    }
  }

  void _changeMode(GeneratorMode mode) {
    _countValid = true;
    _count.text = '${mode == GeneratorMode.passphrase ? _options.wordCount : _options.length}';
    _change(_options.copyWith(mode: mode));
  }

  Future<void> _copy() async {
    if (!_ready || _copying) return;
    final revision = _revision;
    setState(() => _copying = true);
    try {
      final copied = await widget.copy(_value);
      if (!mounted || revision != _revision) return;
      setState(() {
        _copied = copied;
        _error = copied ? null : t.clipboardBusy;
      });
      _copyNotice?.cancel();
      _copyNotice = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void dispose() {
    _revision++;
    _value = '';
    _copyNotice?.cancel();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    alignment: Alignment.topRight,
    insetPadding: const EdgeInsets.fromLTRB(12, 42, 12, 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.generator, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                DesktopIconButton(
                  tooltip: t.generatorClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _GeneratorModeButton(
                    mode: GeneratorMode.password,
                    label: t.generatorPassword,
                    loading: _loading,
                    onChangeMode: _changeMode,
                    options: _options,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _GeneratorModeButton(
                    mode: GeneratorMode.passphrase,
                    label: t.generatorPassphrase,
                    loading: _loading,
                    onChangeMode: _changeMode,
                    options: _options,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GeneratorPreview(
              loading: _loading,
              generating: _generating,
              value: _value,
              copied: _copied,
              countValid: _countValid,
              options: _options,
              onGenerate: _generate,
              ready: _ready,
              copying: _copying,
              onCopy: _copy,
            ),
            const SizedBox(height: 12),
            if (!_loading) ...[
              _GeneratorCount(phrase: _phrase, count: _count, countValid: _countValid, onChangeCount: _changeCount),
              const SizedBox(height: 8),
              if (_phrase)
                _PhraseOptions(options: _options, onChange: _change)
              else
                _PasswordOptions(options: _options, onChange: _change),
              if (!_options.valid) _GeneratorWarning(text: t.generatorChooseGroup),
            ],
            if (_error != null) _GeneratorWarning(text: _error!),
            if (_preferencesError != null) _GeneratorWarning(text: _preferencesError!),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('generator-apply'),
              onPressed: _ready && widget.canApply ? () => Navigator.of(context).pop(_value) : null,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(widget.actionLabel),
            ),
          ],
        ),
      ),
    ),
  );

  void _changeCount(String text) {
    final count = int.tryParse(text);
    _countValid = count != null && count >= (_phrase ? 6 : 12) && count <= (_phrase ? 10 : 64);
    _change(
      _countValid ? (_phrase ? _options.copyWith(wordCount: count) : _options.copyWith(length: count)) : _options,
    );
  }
}
