import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/files/services/file_save_target.dart';

void main() {
  test('renaming an attachment without a suffix retains its original extension', () async {
    expect(
      await FileSaveTarget.resolve(
        selectedPath: r'C:\Exports\renamed',
        suggestedName: 'original.txt',
        exists: (_) async => false,
        confirmReplacement: (_) async => fail('No file to replace'),
      ),
      r'C:\Exports\renamed.txt',
    );
  });

  test('an existing corrected destination requires approval and cancel stops saving', () async {
    final checked = <String>[];
    final result = await FileSaveTarget.resolve(
      selectedPath: r'C:\Exports\renamed',
      suggestedName: 'original.pdf',
      exists: (path) async {
        checked.add(path);
        return true;
      },
      confirmReplacement: (path) async {
        checked.add(path);
        return false;
      },
    );
    expect(result, isNull);
    expect(checked, [r'C:\Exports\renamed.pdf', r'C:\Exports\renamed.pdf']);
  });

  test('replacement approval applies to the complete filename', () async {
    final result = await FileSaveTarget.resolve(
      selectedPath: r'C:\Exports\backup',
      suggestedName: 'vault.smv',
      requireExtension: true,
      exists: (_) async => true,
      confirmReplacement: (path) async => path == r'C:\Exports\backup.smv',
    );
    expect(result, r'C:\Exports\backup.smv');
  });

  test('filesystem collision detection protects both existing files and directories', () async {
    final temporary = await Directory.systemTemp.createTemp('skysecret-save-target-');
    try {
      await File('${temporary.path}/occupied.txt').writeAsString('synthetic');
      await Directory('${temporary.path}/folder.txt').create();
      for (final name in ['occupied', 'folder']) {
        var prompted = false;
        final result = await FileSaveTarget.resolve(
          selectedPath: '${temporary.path}/$name',
          suggestedName: 'attachment.txt',
          confirmReplacement: (_) async {
            prompted = true;
            return false;
          },
        );
        expect(result, isNull);
        expect(prompted, isTrue);
      }
      expect(await File('${temporary.path}/occupied.txt').readAsString(), 'synthetic');
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('an explicitly entered attachment suffix is preserved without a second prompt', () async {
    for (final name in ['renamed.TXT', 'renamed.md']) {
      expect(
        await FileSaveTarget.resolve(
          selectedPath: name,
          suggestedName: 'original.txt',
          exists: (_) async => fail('The native dialog confirmed this exact path'),
          confirmReplacement: (_) async => fail('Unexpected prompt'),
        ),
        name,
      );
    }
  });

  test('vault exports retain smv even when a different suffix was entered', () async {
    expect(
      await FileSaveTarget.resolve(
        selectedPath: 'backup.other',
        suggestedName: 'vault.smv',
        requireExtension: true,
        exists: (_) async => false,
        confirmReplacement: (_) async => false,
      ),
      'backup.other.smv',
    );
  });

  test('files without an extension and dotfiles do not acquire an invented type', () async {
    for (final name in ['LICENSE', '.env', 'name.']) {
      expect(
        await FileSaveTarget.resolve(
          selectedPath: 'renamed',
          suggestedName: name,
          confirmReplacement: (_) async => fail('Unexpected prompt'),
        ),
        'renamed',
      );
    }
  });

  test('directory dots are ignored and trailing dots do not create a double suffix', () async {
    expect(FileSaveTarget.extension(r'C:\directory.v1\file'), isEmpty);
    expect(FileSaveTarget.extension('archive.tar.gz'), 'gz');
    expect(FileSaveTarget.extension('name.t*xt'), isEmpty);
    expect(
      await FileSaveTarget.resolve(
        selectedPath: r'C:\directory.v1\renamed. ',
        suggestedName: 'original.txt',
        exists: (_) async => false,
        confirmReplacement: (_) async => false,
      ),
      r'C:\directory.v1\renamed.txt',
    );
  });
}
