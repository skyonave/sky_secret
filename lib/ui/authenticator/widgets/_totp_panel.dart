part of '../totp_window.dart';

class _TotpPanel extends StatelessWidget {
  final int maxPage;
  final int page;
  final void Function(int) onMovePage;
  final Future<void> Function() onDismiss;
  final List<Map<dynamic, dynamic>> rows;
  final int slots;
  final String? copied;
  final int copiedUntil;
  final bool copying;
  final Future<void> Function(String) onCopy;
  final String? error;

  const _TotpPanel({
    required this.maxPage,
    required this.page,
    required this.onMovePage,
    required this.onDismiss,
    required this.rows,
    required this.slots,
    required this.copied,
    required this.copiedUntil,
    required this.copying,
    required this.onCopy,
    required this.error,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.background,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TotpWindowLayout.tileRadius),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Column(
      children: [
        Container(
          height: TotpWindowLayout.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.verified_user_outlined, size: 14, color: AppColors.muted),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  t.totpTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              if (maxPage > 0) ...[
                const SizedBox(width: 4),
                _TotpPageButton(
                  icon: Icons.keyboard_arrow_up,
                  action: page > 0 ? () => onMovePage(-1) : null,
                  page: page,
                  slots: slots,
                  rows: rows,
                ),
                const SizedBox(width: 2),
                _TotpPageButton(
                  icon: Icons.keyboard_arrow_down,
                  action: page < maxPage ? () => onMovePage(1) : null,
                  page: page,
                  slots: slots,
                  rows: rows,
                ),
              ],
              const SizedBox(width: 4),
              DesktopIconButton(
                tooltip: t.totpClose,
                onPressed: () => unawaited(onDismiss()),
                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                padding: const EdgeInsets.all(5),
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t.totpEmpty,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var slot = 0; slot < slots && page + slot < rows.length; slot++)
                      SizedBox(
                        height: TotpWindowLayout.tileHeight,
                        child: _TotpRow(
                          row: rows[page + slot],
                          copied: copied,
                          copiedUntil: copiedUntil,
                          copying: copying,
                          onCopy: onCopy,
                          error: error,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
