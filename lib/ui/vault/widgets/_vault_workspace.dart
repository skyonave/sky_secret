part of '../vault_panel.dart';

class _VaultWorkspace extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const _VaultWorkspace({required this.controller, required this.child});

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    child: SingleChildScrollView(
      controller: controller,
      key: const Key('vault-workspace'),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
      child: child,
    ),
  );
}
