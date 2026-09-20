part of '../manager_window.dart';

class _ManagerTitleBar extends StatelessWidget {
  final DesktopActions desktop;
  final ValueChanged<bool> onSectionChanged;
  final bool projectsSelected;

  const _ManagerTitleBar({required this.desktop, required this.onSectionChanged, required this.projectsSelected});

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
                  Text(t.appName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        _ManagerSectionButton(
          label: t.general,
          projects: false,
          onSectionChanged: onSectionChanged,
          projectsSelected: projectsSelected,
        ),
        const SizedBox(width: 4),
        _ManagerSectionButton(
          label: t.projects,
          projects: true,
          onSectionChanged: onSectionChanged,
          projectsSelected: projectsSelected,
        ),
        const SizedBox(width: 6),
        DesktopIconButton(
          tooltip: t.hide,
          onPressed: () => unawaited(desktop.hide()),
          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
        ),
      ],
    ),
  );
}
