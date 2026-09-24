part of '../repositories/vault_catalog.dart';

class VaultReference {
  final String id;
  final File file;

  const VaultReference({required this.id, required this.file});

  VaultStore get store => VaultStore(file: file);
}
