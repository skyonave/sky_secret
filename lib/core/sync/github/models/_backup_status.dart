part of '../controllers/github_backup.dart';

enum BackupStatus {
  disconnected,
  ready,
  pending,
  working,
  synced,
  conflict,
  failed,
}
