part of '../manager_window.dart';

class _ManagerFileDropTarget extends StatelessWidget {
  final Widget child;
  final void Function(bool) onSetFileHover;
  final bool canAcceptFiles;
  final String dropHint;
  final ValueChanged<Offset?> onPosition;
  final Future<void> Function(List<String>) onReceiveFiles;
  final bool fileHover;

  const _ManagerFileDropTarget({
    required this.child,
    required this.onSetFileHover,
    required this.canAcceptFiles,
    required this.dropHint,
    required this.onPosition,
    required this.onReceiveFiles,
    required this.fileHover,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ConfigurationWindows.opened,
    builder: (context, configurationOpen, _) => NativeFileDropTarget(
      key: const Key('vault-file-drop'),
      enable: !configurationOpen && (ModalRoute.of(context)?.isCurrent ?? true),
      onHover: onSetFileHover,
      onPosition: onPosition,
      onFiles: (paths) => unawaited(onReceiveFiles(paths)),
      onRejected: () => DesktopNoticeHost.show(context, t.vaultDropReadFailed),
      onUnavailable: () => DesktopNoticeHost.show(context, t.vaultDropUnavailable),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (fileHover && canAcceptFiles == false)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    key: const Key('vault-file-drop-overlay'),
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xF513212D),
                      border: Border.all(color: AppColors.accent, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.file_download_outlined,
                          color: AppColors.accent,
                          size: 38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t.vaultDropTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          dropHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
