import 'package:audiobook_reader/library/secret_store.dart';

/// Fake store with no platform and no external calls.
class TestSecretStore implements SecretStore {
  TestSecretStore([this.value]);

  String? value;
  int reads = 0;
  final List<String> writes = [];
  Object? readError;
  Object? writeError;
  Future<void> Function(String value)? beforeWrite;

  @override
  Future<String?> read() async {
    reads++;
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> write(String value) async {
    await beforeWrite?.call(value);
    if (writeError != null) throw writeError!;
    writes.add(value);
    this.value = value;
  }
}
