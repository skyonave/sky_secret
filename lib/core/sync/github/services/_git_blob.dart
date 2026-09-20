part of 'github_api.dart';

abstract final class GitBlob {
  static Future<String> hash(List<int> bytes) => Isolate.run(() => GitBlob._hash(bytes));

  static Future<String> _hash(List<int> bytes) async {
    final sink = Sha1().newHashSink();
    sink.add(utf8.encode('blob ${bytes.length}\u0000'));
    sink.add(bytes);
    sink.close();
    final hash = await sink.hash();
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
