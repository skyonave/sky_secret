part of '../generator_dialog.dart';

class _PasswordOptions extends StatelessWidget {
  final GeneratorOptions options;
  final void Function(GeneratorOptions) onChange;

  const _PasswordOptions({required this.options, required this.onChange});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: DesktopOption(
              title: 'a–z',
              value: options.lowercase,
              onChanged: (value) => onChange(options.copyWith(lowercase: value)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DesktopOption(
              title: 'A–Z',
              value: options.uppercase,
              onChanged: (value) => onChange(options.copyWith(uppercase: value)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: DesktopOption(
              title: '0–9',
              value: options.digits,
              onChanged: (value) => onChange(options.copyWith(digits: value)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DesktopOption(
              title: t.symbols,
              key: const Key('generator-symbols'),
              value: options.symbols,
              onChanged: (value) => onChange(options.copyWith(symbols: value)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      DesktopTooltip(
        message: t.generatorSimilarHint,
        child: DesktopOption(
          title: t.generatorExcludeSimilar,
          value: options.excludeSimilar,
          onChanged: (value) => onChange(options.copyWith(excludeSimilar: value)),
        ),
      ),
    ],
  );
}
