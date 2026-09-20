part of '../manager_window.dart';

class _GitHubStatus extends StatelessWidget {
  final String label;
  final GitHubBackup? githubBackup;

  const _GitHubStatus({required this.label, required this.githubBackup});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: switch (githubBackup?.status) {
            BackupStatus.synced => const Color(0xFF75D9A0),
            BackupStatus.pending || BackupStatus.working => const Color(0xFFFFCB8A),
            BackupStatus.failed || BackupStatus.conflict => const Color(0xFFFF8F8F),
            _ => AppColors.muted,
          },
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
