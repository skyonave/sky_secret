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
            child: DropdownButtonFormField<String>(
              initialValue: options.separator,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: ['-', ' ', '_', '.']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value == ' ' ? t.generatorSpace : value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) onChange(options.copyWith(separator: value));
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(t.generatorEnglishWords, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ],
  );
}
