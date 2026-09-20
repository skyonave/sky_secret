part of '../totp_window.dart';

class _TotpPageButton extends StatelessWidget {
  final IconData icon;
  final void Function()? action;
  final int page;
  final int slots;
  final List<Map<dynamic, dynamic>> rows;

  const _TotpPageButton({
    required this.icon,
    required this.action,
    required this.page,
    required this.slots,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) => DesktopIconButton(
    tooltip: '${page + 1}–${(page + slots).clamp(0, rows.length)} / ${rows.length}',
    style: IconButton.styleFrom(
      minimumSize: const Size(20, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    constraints: const BoxConstraints.tightFor(width: 20, height: 20),
    padding: const EdgeInsets.all(3),
    onPressed: action,
    icon: Icon(icon, size: 14),
  );
}
