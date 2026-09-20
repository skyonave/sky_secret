part of '../generator_dialog.dart';

class _GeneratorModeButton extends StatelessWidget {
  final GeneratorMode mode;
  final String label;
  final bool loading;
  final void Function(GeneratorMode) onChangeMode;
  final GeneratorOptions options;

  const _GeneratorModeButton({
    required this.mode,
    required this.label,
    required this.loading,
    required this.onChangeMode,
    required this.options,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: loading ? null : () => onChangeMode(mode),
    style: TextButton.styleFrom(
      backgroundColor: options.mode == mode ? AppColors.surface : Colors.transparent,
      side: BorderSide(color: options.mode == mode ? AppColors.accent : AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    ),
    child: Text(label),
  );
}
