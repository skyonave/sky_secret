part of '../manager_window.dart';

class _ManagerSectionButton extends StatelessWidget {
  final String label;
  final bool projects;
  final ValueChanged<bool> onSectionChanged;
  final bool projectsSelected;

  const _ManagerSectionButton({
    required this.label,
    required this.projects,
    required this.onSectionChanged,
    required this.projectsSelected,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => onSectionChanged(projects),
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(fontSize: 12),
      foregroundColor: projectsSelected == projects ? AppColors.accent : AppColors.muted,
      backgroundColor: projectsSelected == projects ? AppColors.background : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    child: Text(label),
  );
}
