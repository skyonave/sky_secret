part of '../generator_dialog.dart';

class _GeneratorPreview extends StatelessWidget {
  final bool loading;
  final bool generating;
  final String value;
  final bool copied;
  final bool countValid;
  final GeneratorOptions options;
  final Future<void> Function() onGenerate;
  final bool ready;
  final bool copying;
  final Future<void> Function() onCopy;

  const _GeneratorPreview({
    required this.loading,
    required this.generating,
    required this.value,
    required this.copied,
    required this.countValid,
    required this.options,
    required this.onGenerate,
    required this.ready,
    required this.copying,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42, maxHeight: 110),
          child: loading || generating
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : SingleChildScrollView(
                  child: Text(
                    value,
                    key: const Key('generated-password'),
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 15, height: 1.45),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (copied) Padding(padding: const EdgeInsets.only(right: 8), child: Text(t.copied)),
            DesktopIconButton(
              key: const Key('generator-regenerate'),
              tooltip: t.regenerate,
              onPressed: !loading && countValid && options.valid ? () => unawaited(onGenerate()) : null,
              icon: const Icon(Icons.refresh_rounded, size: 17),
            ),
            const SizedBox(width: 4),
            DesktopIconButton(
              key: const Key('generator-copy'),
              tooltip: t.copy,
              onPressed: ready && !copying ? () => unawaited(onCopy()) : null,
              icon: Icon(copied ? Icons.check_rounded : Icons.copy_outlined, size: 17),
            ),
          ],
        ),
      ],
    ),
  );
}
