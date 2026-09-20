part of '../repositories/vault_catalog.dart';

class VaultReference {
  final String id;
  final File file;
  final bool isProject;

  const VaultReference({required this.id, required this.file, this.isProject = false});

  VaultStore get store => VaultStore(file: file);
}
