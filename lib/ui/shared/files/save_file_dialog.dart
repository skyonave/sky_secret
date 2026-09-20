import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/files/services/file_save_target.dart';
import '../../../core/desktop/configuration/controllers/configuration_windows.dart';
import '../../../i18n/translations.g.dart';

abstract final class SaveFileDialog {
  static Future<File?> select({
    required BuildContext context,
    required String suggestedName,
    required bool Function() allowed,
    bool requireExtension = false,
  }) async {
    final extension = FileSaveTarget.extension(suggestedName);
    final destination = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        if (extension.isNotEmpty) XTypeGroup(label: '*.$extension', extensions: [extension]),
      ],
    );
    if (destination == null || !context.mounted || !allowed()) return null;
    final path = await FileSaveTarget.resolve(
      selectedPath: destination.path,
      suggestedName: suggestedName,
      requireExtension: requireExtension,
      confirmReplacement: (path) async {
        if (!context.mounted || !allowed()) return false;
        return await ConfigurationWindows.open(
              kind: 'confirm',
              locale: LocaleSettings.currentLocale.languageCode,
              isValid: () => context.mounted && allowed(),
              data: {
                'title': t.fileReplaceTitle,
                'message': t.fileReplaceBody(path: path),
                'action': t.fileReplace,
              },
            ) ==
            true;
      },
    );
    if (path == null || !context.mounted || !allowed()) return null;
    return File(path);
  }
}
