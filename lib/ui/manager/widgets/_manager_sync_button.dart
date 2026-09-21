part of '../manager_window.dart';

class _ManagerSyncButton extends StatelessWidget {
  final GitHubBackup? githubBackup;
  final ButtonStyle footerButtonStyle;
  final Future<void> Function(GitHubBackup) onSync;

  const _ManagerSyncButton({required this.githubBackup, required this.footerButtonStyle, required this.onSync});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: githubBackup!,
    builder: (context, _) {
      final backup = githubBackup!;
      return DesktopTooltip(
        message: backup.busy ? t.syncWorking : t.syncNow,
        child: Stack(
          children: [
            TextButton.icon(
              key: const Key('synchronize-vault'),
              style: footerButtonStyle,
              onPressed: backup.busy || !backup.usable
                  ? null
                  : () {
                      unawaited(onSync(backup));
                    },
              icon: const Icon(Icons.sync_rounded, size: 15),
              label: Text(t.desktopSync),
            ),
            if (backup.busy)
              const Positioned(left: 8, right: 8, bottom: 0, child: LinearProgressIndicator(minHeight: 2)),
          ],
        ),
      );
    },
  );
}
