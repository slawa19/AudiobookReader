/// Storage for a single secret — the Gemini key. The implementation is provided by the assembly root.
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// The platform error text may contain the secret, so it does not go outside.
class SecretStoreException implements Exception {
  const SecretStoreException();

  @override
  String toString() => 'Could not access the secure key storage';
}
