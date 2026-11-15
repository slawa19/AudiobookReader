/// Хранилище одного секрета — ключа Gemini. Реализацию подставляет корень сборки.
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Текст платформенной ошибки может содержать секрет, поэтому наружу он не выходит.
class SecretStoreException implements Exception {
  const SecretStoreException();

  @override
  String toString() => 'Не удалось обратиться к защищённому хранилищу ключа';
}
