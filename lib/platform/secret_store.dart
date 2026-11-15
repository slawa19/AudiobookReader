import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../library/secret_store.dart';

/// Ключ Gemini в защищённом хранилище Android; пакет доступен только платформе.
class AndroidSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'gemini_api_key';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      throw const SecretStoreException();
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {
      throw const SecretStoreException();
    }
  }
}
