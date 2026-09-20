import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../os/windows/services/windows_dpapi.dart';
import '../../storage/app_data_directory.dart';
import '../../storage/local_file.dart';
import '../models/project_launch_profile.dart';

class ProjectLaunchPreferences {
  final File file;
  final Uint8List Function(List<int>, {bool decrypt}) protect;
  Future<void> _saving = Future.value();

  ProjectLaunchPreferences({required this.file, this.protect = DeviceProtection.protect});

  factory ProjectLaunchPreferences.local() => ProjectLaunchPreferences(
    file: File('${AppDataDirectory.resolve().path}${Platform.pathSeparator}project_launch.dpapi'),
  );

  Future<Map<String, dynamic>> _read() async {
    final bytes = await LocalFile.readBounded(file, maxBytes: 1024 * 1024);
    if (bytes == null) return {};
    final plain = protect(bytes, decrypt: true);
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<ProjectLaunchProfile?> read(String id) async {
    await _saving;
    final value = (await _read())[id];
    return value == null ? null : ProjectLaunchProfile.fromJson(value as Map);
  }

  Future<void> save(String id, ProjectLaunchProfile profile) {
    final operation = _saving.then((_) async {
      final profiles = await _read();
      profiles[id] = profile.toJson();
      final plain = utf8.encode(jsonEncode(profiles));
      try {
        if (plain.length > 1024 * 1024) throw const FormatException('Launch settings too large');
        await LocalFile.writeAtomic(file, protect(plain, decrypt: false));
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    });
    _saving = operation.catchError((_) {});
    return operation;
  }
}
