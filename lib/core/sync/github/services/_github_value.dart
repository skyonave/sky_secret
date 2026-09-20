part of 'github_api.dart';

abstract final class GitHubValue {
  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return value;
  }

  static String string(Object? value) {
    if (value is! String || value.isEmpty || value.length > 1024) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return value;
  }

  static int positiveInt(Object? value) {
    if (value is! int || value <= 0) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return value;
  }

  static String sha(Object? value) {
    final result = GitHubValue.string(value);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(result)) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return result;
  }

  static const randomBackupIdPattern = r'^[0-9a-f]{32}$';

  static String backupId(Object? value) {
    final result = GitHubValue.string(value);
    if (!RegExp(GitHubValue.randomBackupIdPattern).hasMatch(result)) {
      throw const GitHubFailure(GitHubProblem.format);
    }
    return result;
  }
}
