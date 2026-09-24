import '../../crypto/vault/models/project_environment.dart';

/// Parses data only: never expands variables or executes shell expressions.
abstract final class ProjectDotenv {
  static ProjectEnvironment parse(String source) {
    if (source.length > 65536) throw const FormatException('Environment too large');
    final values = <String, String>{};
    final names = <String>{};
    final lines = source.replaceFirst(RegExp(r'^\uFEFF'), '').split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index++) {
      var line = lines[index].trimLeft();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
      final separator = line.indexOf('=');
      if (separator < 1) throw FormatException('line', index + 1);
      final name = line.substring(0, separator).trim();
      if (!ProjectEnvironment.validName(name) || !names.add(name.toUpperCase())) {
        throw FormatException('line', index + 1);
      }
      var value = line.substring(separator + 1).trimLeft();
      if (value.startsWith('"') || value.startsWith("'")) {
        final quote = value[0];
        final decoded = StringBuffer();
        var closed = false;
        for (var offset = 1; ; offset++) {
          if (offset >= value.length) {
            if (index + 1 >= lines.length) break;
            value += '\n${lines[++index]}';
          }
          final char = value[offset];
          if (char == quote) {
            final tail = value.substring(offset + 1).trim();
            if (tail.isNotEmpty && !tail.startsWith('#')) throw FormatException('line', index + 1);
            closed = true;
            break;
          }
          if (char == r'\' && quote == '"' && offset + 1 < value.length) {
            final next = value[++offset];
            decoded.write(switch (next) {
              'n' => '\n',
              'r' => '\r',
              't' => '\t',
              '"' => '"',
              r'\' => r'\',
              _ => '\\$next',
            });
          } else {
            decoded.write(char);
          }
        }
        if (!closed) throw FormatException('line', index + 1);
        value = decoded.toString();
      } else {
        final comment = RegExp(r'\s+#').firstMatch(value);
        if (value.startsWith('#')) {
          value = '';
        } else if (comment != null) {
          value = value.substring(0, comment.start);
        }
        value = value.trimRight();
      }
      values[name] = value;
    }
    return ProjectEnvironment(values);
  }

  static String format(ProjectEnvironment environment) => environment.variables.entries
      .map((entry) {
        final value = entry.value
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"')
            .replaceAll('\n', r'\n')
            .replaceAll('\r', r'\r')
            .replaceAll('\t', r'\t');
        return '${entry.key}="$value"';
      })
      .join('\n');
}
