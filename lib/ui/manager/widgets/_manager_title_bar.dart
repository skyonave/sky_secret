part of '../manager_window.dart';

class _ManagerTitleBar extends StatelessWidget {
  final DesktopActions desktop;
  final bool unlocked;
  final VoidCallback onLock;

  const _ManagerTitleBar({
    required this.desktop,
    required this.unlocked,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => unawaited(desktop.drag()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DesktopIconButton(
          key: const Key('lock-vault'),
          tooltip: t.vaultLock,
          onPressed: unlocked ? onLock : null,
          icon: const Icon(Icons.lock_outline_rounded, size: 17),
        ),
        const SizedBox(width: 4),
        DesktopIconButton(
          tooltip: t.hide,
          onPressed: () => unawaited(desktop.hide()),
          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
        ),
      ],
    ),
  );
}
