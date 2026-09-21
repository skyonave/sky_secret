part of '../generator_dialog.dart';

class _PhraseOptions extends StatelessWidget {
  final GeneratorOptions options;
  final void Function(GeneratorOptions) onChange;

  const _PhraseOptions({required this.options, required this.onChange});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(t.generatorSeparator)),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: DesktopSelect<String>(
              value: options.separator,
              items: [
                for (final value in ['-', ' ', '_', '.'])
                  (value: value, label: value == ' ' ? t.generatorSpace : value, icon: Icons.short_text_rounded),
              ],
              onChanged: (value) => onChange(options.copyWith(separator: value)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(t.generatorEnglishWords, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ],
  );
}
