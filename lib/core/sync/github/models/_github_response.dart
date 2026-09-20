part of '../services/github_api.dart';

enum GitHubProblem {
  network,
  authorization,
  denied,
  missing,
  conflict,
  repositoryChanged,
  repositorySetup,
  format,
  storage,
  identity,
  cancelled,
  configuration,
}

class GitHubFailure implements Exception {
  final GitHubProblem problem;
  final Duration? retryAfter;

  const GitHubFailure(this.problem, {this.retryAfter});

  @override
  String toString() => 'GitHubFailure(${problem.name})';
}

class GitHubResponse {
  final int status;
  final Object? body;
  final Map<String, String> headers;

  const GitHubResponse(
    this.status,
    this.body, [
    this.headers = const {},
  ]);
}

typedef GitHubTransport = Future<GitHubResponse> Function(
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
  int limit,
);
