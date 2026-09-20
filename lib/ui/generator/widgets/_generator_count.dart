part of '../generator_dialog.dart';

class _GeneratorCount extends StatelessWidget {
  final bool phrase;
  final TextEditingController count;
  final bool countValid;
  final void Function(String) onChangeCount;

  const _GeneratorCount({
    required this.phrase,
    required this.count,
    required this.countValid,
    required this.onChangeCount,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(phrase ? '${t.generatorWords} · 6–10' : '${t.length} · 12–64'),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 120,
        child: SensitiveTextEditing(
          controller: count,
          builder: (context, menuBuilder) => TextField(
            contextMenuBuilder: menuBuilder,
            enableIMEPersonalizedLearning: false,
            key: const Key('generator-count'),
            controller: count,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              errorText: countValid ? null : t.generatorRange,
            ),
            onChanged: onChangeCount,
          ),
        ),
      ),
    ],
  );
}
