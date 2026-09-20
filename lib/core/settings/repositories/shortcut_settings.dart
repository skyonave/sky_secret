import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

import '../../storage/app_data_directory.dart';
import '../../storage/local_file.dart';
part '../models/_system_shortcuts.dart';

class ShortcutStore {
  final File file;

  ShortcutStore({File? file})
    : file =
          file ??
          File(
            '${AppDataDirectory.resolve().path}${Platform.pathSeparator}settings.json',
          );

  factory ShortcutStore.search() => ShortcutStore(
    file: File('${AppDataDirectory.resolve().path}${Platform.pathSeparator}search_shortcut.json'),
  );

  Future<HotKey?> load() async {
    final bytes = await LocalFile.readBounded(file, maxBytes: 16 * 1024);
    if (bytes == null) return null;
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown settings version');
    }
    final key = HotKey.fromJson(json['shortcut'] as Map<String, dynamic>);
    if (!SystemShortcuts.isValid(key)) throw const FormatException('Invalid shortcut');
    return key;
  }

  Future<void> save(HotKey key) async {
    if (!SystemShortcuts.isValid(key)) throw const FormatException('Invalid shortcut');
    await LocalFile.writeAtomic(
      file,
      utf8.encode(jsonEncode({'version': 1, 'shortcut': key.toJson()})),
    );
  }
}
