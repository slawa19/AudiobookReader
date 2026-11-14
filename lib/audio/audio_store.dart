// Хранилище звука отрезков и проб (ARCHITECTURE.md, раздел 6.5). Экранам отсюда нужно только занятое место.

abstract class AudioStore {
  /// Байт озвучки одной книги.
  int bytesForBook(String bookId);

  /// Байт озвучки всех книг и проб.
  int get totalBytes;
}

/// Подставное хранилище прототипа: числа, а не файлы. Удаляет только `playback` (А§2).
class FakeAudioStore implements AudioStore {
  FakeAudioStore(Map<String, int> bytesByBook, {this.samplesBytes = 3 * 1024 * 1024})
      : _bytes = Map.of(bytesByBook);

  final Map<String, int> _bytes;
  int samplesBytes;

  @override
  int bytesForBook(String bookId) => _bytes[bookId] ?? 0;

  @override
  int get totalBytes => _bytes.values.fold(0, (a, b) => a + b) + samplesBytes;

  void removeBook(String bookId) => _bytes.remove(bookId);

  void clearAll() {
    _bytes.clear();
    samplesBytes = 0;
  }
}
