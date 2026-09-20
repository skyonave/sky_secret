part of '../manager_window.dart';

class _ManagerFooter extends StatelessWidget {
  final GitHubBackup? githubBackup;
  final ButtonStyle footerButtonStyle;
  final ValueChanged<GitHubBackup> onShowGitHub;
  final Future<void> Function(GitHubBackup) onSync;
  final DesktopActions desktop;

  const _ManagerFooter({
    required this.githubBackup,
    required this.footerButtonStyle,
    required this.onShowGitHub,
    required this.onSync,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('manager-footer'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: githubBackup == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DefaultTextStyle(
                    style: const TextStyle(fontFamily: 'Segoe UI', color: AppColors.muted, fontSize: 11),
                    child: _GitHubStatus(label: t.githubDisconnected, githubBackup: githubBackup),
                  ),
                )
              : ListenableBuilder(
                  listenable: githubBackup!,
                  builder: (context, _) => DesktopTooltip(
                    message: GitHubLabels.status(githubBackup!),
                    child: TextButton(
                      style: footerButtonStyle,
                      onPressed: () => onShowGitHub(githubBackup!),
                      child: _GitHubStatus(label: GitHubLabels.status(githubBackup!), githubBackup: githubBackup),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 4),
        if (githubBackup != null)
          _ManagerSyncButton(githubBackup: githubBackup, footerButtonStyle: footerButtonStyle, onSync: onSync),
        const SizedBox(width: 4),
        DesktopIconButton(
          key: const Key('shortcut-settings'),
          tooltip: t.keyboardShortcuts,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ShortcutDialog(desktop: desktop),
          ),
          icon: const Icon(Icons.keyboard_outlined, size: 17, color: AppColors.muted),
        ),
      ],
    ),
  );
}
