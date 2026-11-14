import 'package:flutter/foundation.dart';

// Хранилище звука отрезков и проб (ARCHITECTURE.md, раздел 6.5). Экранам отсюда нужно только занятое место;
// удаляет звук только `playback` (А§2, А§4).
//
// Операции записи и чтения файлов (`has/file/put`) появятся вместе с очередью синтеза — прототипу они не нужны.

abstract class AudioStore extends ChangeNotifier {
  /// Байт озвучки одной книги.
  int bytesForBook(String bookId);

  /// Байт озвучки всех книг и проб.
  int get totalBytes;

  void removeBook(String bookId);

  /// Звук всех книг и проб.
  void clearAll();
}

/// Подставное хранилище прототипа: числа, а не файлы.
class FakeAudioStore extends AudioStore {
  FakeAudioStore(Map<String, int> bytesByBook, {this.samplesBytes = 3 * 1024 * 1024})
      : _bytes = Map.of(bytesByBook);

  final Map<String, int> _bytes;
  int samplesBytes;

  @override
  int bytesForBook(String bookId) => _bytes[bookId] ?? 0;

  @override
  int get totalBytes => _bytes.values.fold(0, (a, b) => a + b) + samplesBytes;

  @override
  void removeBook(String bookId) {
    _bytes.remove(bookId);
    notifyListeners();
  }

  @override
  void clearAll() {
    _bytes.clear();
    samplesBytes = 0;
    notifyListeners();
  }
}
