import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/projects/services/project_dotenv.dart';
import 'package:skysecret/core/projects/services/project_env_import.dart';

void main() {
  test('source removal cannot delete a replacement written after comparison', () async {
    final directory = await Directory.systemTemp.createTemp('project-env-delete-race-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/.env');
    await file.writeAsString('TOKEN=synthetic');
    final sources = await ProjectEnvImport.scan(directory, allowed: () => true);
    addTearDown(() => sources.single.clear());
    var checks = 0;
    var replaced = false;
    final removed = await sources.single.removeUnchanged(
      allowed: () {
        checks++;
        if (checks >= 3) {
          try {
            file.writeAsStringSync('TOKEN=changed');
            replaced = true;
          } on FileSystemException {
            return true;
          }
        }
        return true;
      },
    );
    if (replaced) {
      expect(removed, isFalse);
      expect(await file.readAsString(), 'TOKEN=changed');
    } else {
      expect(removed, isTrue);
      expect(await file.exists(), isFalse);
    }
  });

  test('quoted multiline values preserve trailing whitespace on the first line', () {
    for (final quote in ['"', "'"]) {
      final environment = ProjectDotenv.parse('KEY=${quote}first  \t\nsecond$quote');
      expect(environment.variables['KEY'], 'first  \t\nsecond');
    }
  });

  test('dotenv handles empty values, quotes, comments, CRLF, BOM and literal expressions', () {
    final env = ProjectDotenv.parse(
      '\uFEFF# comment\r\nexport TOKEN="synthetic=a#b" # note\r\nEMPTY=""\r\nBLANK=\r\nNAME=hello # comment\r\nLITERAL=\'\${TOKEN}\'\r\nMULTI="line1\\nline2"',
    );
    expect(env.variables, {
      'TOKEN': 'synthetic=a#b',
      'EMPTY': '',
      'BLANK': '',
      'NAME': 'hello',
      'LITERAL': r'${TOKEN}',
      'MULTI': 'line1\nline2',
    });
    expect(ProjectDotenv.parse('  \n# only a comment').variables, isEmpty);
  });
  test('quoted multiline values are preserved without shell evaluation', () {
    final value = ProjectDotenv.parse('KEY="line one\nline two"\nOTHER=literal');
    expect(value.variables, {'KEY': 'line one\nline two', 'OTHER': 'literal'});
  });
  test('empty values followed by comments accept additional hash characters', () {
    expect(ProjectDotenv.parse('EMPTY=# one # two\nNEXT=ok').variables, {'EMPTY': '', 'NEXT': 'ok'});
  });
  test('dotenv export round trips all supported value characters', () {
    final env = ProjectEnvironment({
      'PATH': r'C:\synthetic\tools',
      'QUOTES': '"hello"',
      'TABS': 'a\tb',
      'LINES': 'a\r\nb',
      'EMPTY': '',
      'UNICODE': 'тест 😀',
      'EXPRESSION': r'$(whoami) ${TOKEN}',
      'SPACE': '  padded  ',
    });
    expect(ProjectDotenv.parse(ProjectDotenv.format(env)).variables, env.variables);
  });
  test('invalid syntax and ambiguous names fail without exposing contents in errors', () {
    for (final text in [
      'A=x\na=y',
      'A="unclosed',
      'A="x" trailing',
      '1BAD=value',
      'MISSING',
      'A=\u0000',
      'A=${'x' * 24000}',
    ]) {
      expect(() => ProjectDotenv.parse(text), throwsFormatException);
    }
    try {
      ProjectDotenv.parse('A=ok\nSECRET="synthetic-sensitive');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('synthetic-sensitive')));
      expect(error.source, 2);
    }
  });
  test('folder scan skips templates/dependencies and reports malformed files without changing sources', () async {
    final directory = await Directory.systemTemp.createTemp('project-env-synthetic-');
    addTearDown(() => directory.delete(recursive: true));
    for (final name in [
      '.env',
      '.env.local',
      '.env.example',
      '.env.template',
      '.env.sample',
      'node_modules/a/.env',
      'nested/.env.production',
    ]) {
      final file = File('${directory.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsString('TOKEN=synthetic');
    }
    await File('${directory.path}/.env.bad').writeAsString('INVALID');
    final sources = await ProjectEnvImport.scan(directory, allowed: () => true);
    addTearDown(() {
      for (final source in sources) {
        source.clear();
      }
    });
    expect(sources.length, 4);
    expect(sources.where((source) => source.invalid).length, 1);
    expect(await File('${directory.path}/.env').readAsString(), 'TOKEN=synthetic');
    final source = sources.firstWhere((source) => source.name == '.env');
    expect(await source.removeUnchanged(allowed: () => false), false);
    await File(source.path).writeAsString('TOKEN=changed');
    expect(await source.removeUnchanged(allowed: () => true), false);
    expect(await File(source.path).exists(), true);
    await File(source.path).writeAsString('TOKEN=synthetic');
    expect(await source.removeUnchanged(allowed: () => true), true);
    expect(await File(source.path).exists(), false);
    expect(await File('${directory.path}/.env.example').exists(), true);
  });
  test('cancelled folder scan imports nothing', () async {
    final directory = await Directory.systemTemp.createTemp('project-env-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/.env').writeAsString('TOKEN=synthetic');
    await expectLater(ProjectEnvImport.scan(directory, allowed: () => false), throwsA(isA<FileSystemException>()));
    expect(await File('${directory.path}/.env').exists(), true);
  });
}
