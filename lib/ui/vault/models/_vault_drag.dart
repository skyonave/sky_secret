part of '../vault_panel.dart';

class _VaultDrag {
  final VaultSession session;
  final VaultItem item;

  const _VaultDrag(this.session, this.item);
}

class _VaultInsertion {
  final String? parentId;
  final String? beforeKey;

  const _VaultInsertion(this.parentId, this.beforeKey);

  ({String? parentId, String? beforeKey}) get key => (parentId: parentId, beforeKey: beforeKey);
}
