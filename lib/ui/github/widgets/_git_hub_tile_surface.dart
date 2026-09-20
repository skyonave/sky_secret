part of '../github_dialog.dart';

class _GitHubTileSurface extends StatelessWidget {
  final Widget child;

  const _GitHubTileSurface({required this.child});

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    shape: _GitHubDialogState._controlShape,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
