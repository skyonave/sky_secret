class ProjectLaunchProfile {
  final String executable;
  final String directory;
  final List<String> arguments;

  ProjectLaunchProfile({
    required this.executable,
    required this.directory,
    required List<String> arguments,
  }) : arguments = List.unmodifiable(arguments) {
    if (!RegExp(r'^[A-Za-z]:[\\/]').hasMatch(executable) ||
        !executable.toLowerCase().endsWith('.exe') ||
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(directory) ||
        [executable, directory, ...arguments].any((value) => value.contains('\u0000')) ||
        arguments.length > 128 ||
        [executable, directory, ...arguments].join().length > 16000) {
      throw const FormatException('Invalid launch profile');
    }
  }

  void checkSecrets(Iterable<String> secrets) {
    for (final secret in secrets) {
      if (secret.length < 4) continue;
      if ([executable, directory, ...arguments].any((value) => value.contains(secret))) {
        throw const FormatException('Secret in launch configuration');
      }
    }
  }

  Map<String, dynamic> toJson() => {'executable': executable, 'directory': directory, 'arguments': arguments};

  factory ProjectLaunchProfile.fromJson(Map data) => ProjectLaunchProfile(
    executable: data['executable'] as String,
    directory: data['directory'] as String,
    arguments: (data['arguments'] as List).cast<String>(),
  );
}
