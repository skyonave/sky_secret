part of '../generator_dialog.dart';

class _GeneratorWarning extends StatelessWidget {
  final String text;

  const _GeneratorWarning({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: const TextStyle(color: Color(0xFFFFCB8A), fontSize: 11)),
  );
}
