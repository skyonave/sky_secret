part of '../totp_window.dart';

class _TotpRow extends StatelessWidget {
  final Map<dynamic, dynamic> row;
  final String? copied;
  final int copiedUntil;
  final bool copying;
  final Future<void> Function(String) onCopy;
  final String? error;

  const _TotpRow({
    required this.row,
    required this.copied,
    required this.copiedUntil,
    required this.copying,
    required this.onCopy,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final period = (row['period'] as int) * 1000;
    final remaining = ((row['expires'] as int) - now).clamp(0, period);
    final valid = remaining > 0 && now >= (row['expires'] as int) - period;
    final code = row['code'] as String;
    final midpoint = code.length ~/ 2;
    final copied = this.copied == row['id'] && now < copiedUntil;
    final progressColor = remaining <= 5000 ? const Color(0xFFFFCB8A) : AppColors.muted;
    final copy = valid && !copying ? () => onCopy(row['id'] as String) : null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: copy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row['title'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(remaining / 1000).ceil()} ${t.totpSeconds}',
                      style: TextStyle(fontSize: 10, height: 1.1, color: progressColor),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          valid ? '${code.substring(0, midpoint)} ${code.substring(midpoint)}' : '—',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1,
                            fontFamily: 'Consolas',
                            letterSpacing: 1,
                            color: Color(0xFFE4F4FA),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    DesktopIconButton(
                      tooltip: error ?? (copied ? t.copied : t.totpCopy),
                      onPressed: copy,
                      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                      padding: const EdgeInsets.all(6),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: Icon(
                        error != null
                            ? Icons.error_outline
                            : copied
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                        size: 14,
                        color: error != null
                            ? const Color(0xFFFF8F8F)
                            : copied
                            ? const Color(0xFF75D9A0)
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: remaining / period,
                  minHeight: 2,
                  stopIndicatorRadius: 0,
                  trackGap: 0,
                  borderRadius: BorderRadius.circular(1),
                  color: progressColor,
                  backgroundColor: AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
