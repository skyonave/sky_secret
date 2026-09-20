import 'dart:convert';

class ProjectEnvironment {
  final Map<String, String> variables;

  ProjectEnvironment(Map<String, String> variables) : variables = Map.unmodifiable(variables) {
    final names = <String>{};
    var size = 1;
    if (variables.length > 128) throw const FormatException('Too many variables');
    for (final item in variables.entries) {
      if (!validName(item.key) || !names.add(item.key.toUpperCase()) || item.value.contains('\u0000')) {
        throw const FormatException('Invalid environment variable');
      }
      size += item.key.length + item.value.length + 2;
    }
    if (size > 24000) throw const FormatException('Environment too large');
  }

  static bool validName(String name) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$').hasMatch(name);

  String encode() => jsonEncode({'version': 1, 'variables': variables});

  factory ProjectEnvironment.decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map || data.length != 2 || data['version'] != 1 || data['variables'] is! Map) {
      throw const FormatException('Invalid project environment');
    }
    final variables = <String, String>{};
    for (final entry in (data['variables'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) throw const FormatException('Invalid variable');
      variables[entry.key as String] = entry.value as String;
    }
    return ProjectEnvironment(variables);
  }
}
