part of '../services/vault_cipher.dart';

class VaultProject {
  final String id;
  final String vaultId;
  final String lineage;
  final String name;
  final String? conflictOf;
  final bool archived;
  final ProtectedText _credential;

  VaultProject({
    required this.id,
    required this.vaultId,
    required this.lineage,
    required this.name,
    String credential = '',
    this.conflictOf,
    this.archived = false,
  }) : _credential = ProtectedText(credential) {
    if (id.isEmpty ||
        id.length > 128 ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(vaultId) ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(lineage) ||
        name.trim().isEmpty ||
        name.length > 120 ||
        credential.length > 1024 ||
        (credential.isNotEmpty && !MasterPasswordPolicy.accepts(credential)) ||
        (conflictOf != null && (conflictOf!.isEmpty || conflictOf!.length > 128))) {
      _credential.destroy();
      throw const VaultFormatException();
    }
  }

  VaultProject._owned(VaultProject source, SecretLifetime lifetime)
    : id = source.id,
      vaultId = source.vaultId,
      lineage = source.lineage,
      name = source.name,
      conflictOf = source.conflictOf,
      archived = source.archived,
      _credential = source._credential.ownFor(lifetime);

  bool get unlockWithWorkspace => !_credential.isEmpty;
  String get credential => _credential.read();

  VaultProject renamed(String name) => VaultProject(
    id: id,
    vaultId: vaultId,
    lineage: lineage,
    name: name,
    credential: credential,
    conflictOf: conflictOf,
    archived: archived,
  );

  VaultProject withArchived(bool value) => VaultProject(
    id: id,
    vaultId: vaultId,
    lineage: lineage,
    name: name,
    credential: credential,
    conflictOf: conflictOf,
    archived: value,
  );

  VaultProject resolved() =>
      VaultProject(id: id, vaultId: vaultId, lineage: lineage, name: name, credential: credential, archived: false);

  Map<String, dynamic> toJson() => {
    _VaultProjectJson.id: id,
    _VaultProjectJson.vaultId: vaultId,
    _VaultProjectJson.lineage: lineage,
    _VaultProjectJson.name: name,
    _VaultProjectJson.credential: credential,
    _VaultProjectJson.conflictOf: conflictOf,
    _VaultProjectJson.archived: archived,
  };

  static VaultProject fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value.length != 7 ||
        value[_VaultProjectJson.archived] is! bool ||
        ![
          _VaultProjectJson.id,
          _VaultProjectJson.vaultId,
          _VaultProjectJson.lineage,
          _VaultProjectJson.name,
          _VaultProjectJson.credential,
        ].every((key) => value[key] is String) ||
        !value.containsKey(_VaultProjectJson.conflictOf) ||
        (value[_VaultProjectJson.conflictOf] != null && value[_VaultProjectJson.conflictOf] is! String)) {
      throw const VaultFormatException();
    }
    return VaultProject(
      id: value[_VaultProjectJson.id],
      vaultId: value[_VaultProjectJson.vaultId],
      lineage: value[_VaultProjectJson.lineage],
      name: value[_VaultProjectJson.name],
      credential: value[_VaultProjectJson.credential],
      conflictOf: value[_VaultProjectJson.conflictOf],
      archived: value[_VaultProjectJson.archived],
    );
  }

  VaultEntry toMergeEntry() => VaultEntry(
    id: id,
    title: name,
    username: vaultId,
    password: credential,
    notes: lineage,
    conflictOf: conflictOf,
    deletedAt: archived ? 1 : null,
  );

  static VaultProject fromMergeEntry(VaultEntry entry) => VaultProject(
    id: entry.id,
    vaultId: entry.username,
    lineage: entry.notes,
    name: entry.title,
    credential: entry.password,
    conflictOf: entry.conflictOf,
    archived: entry.isDeleted,
  );
}

abstract final class _VaultProjectJson {
  static const id = 'id';
  static const vaultId = 'vaultId';
  static const lineage = 'lineage';
  static const name = 'name';
  static const credential = 'credential';
  static const conflictOf = 'conflictOf';
  static const archived = 'archived';
}
