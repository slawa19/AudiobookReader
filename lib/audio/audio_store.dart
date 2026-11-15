import 'dart:io';

import 'package:flutter/foundation.dart';

// Хранилище звука отрезков и проб (ARCHITECTURE.md, раздел 6.5). Экранам отсюда нужно только занятое место;
// удаляет звук только `playback` (А§2, А§4).

abstract class AudioStore extends ChangeNotifier {
  String get formatId;

  /// Без bookId — общая проба голоса, с bookId — отрезок книги.
  bool has(String fingerprint, {String? bookId});

  /// Только готовый файл; отсутствующий звук — null.
  File? file(String fingerprint, {String? bookId});

  /// PCM не меняется и остаётся у очереди для повтора записи без нового синтеза.
  /// Удаление во время записи завершает её ошибкой AudioWriteCancelled.
  Future<File> put(
    String fingerprint,
    Uint8List pcm,
    int sampleRate, {
    String? bookId,
  });

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
  FakeAudioStore(
    Map<String, int> bytesByBook, {
    this.samplesBytes = 3 * 1024 * 1024,
  }) : _bytes = Map.of(bytesByBook);

  final Map<String, int> _bytes;
  int samplesBytes;
  final Map<(String?, String), int> _files = {};

  @override
  String get formatId => 'fake-pcm16-mono-v1';

  @override
  bool has(String fingerprint, {String? bookId}) =>
      _files.containsKey((bookId, fingerprint));

  @override
  File? file(String fingerprint, {String? bookId}) =>
      has(fingerprint, bookId: bookId)
      ? File('fake/${bookId ?? 'samples'}/$fingerprint.wav')
      : null;

  @override
  Future<File> put(
    String fingerprint,
    Uint8List pcm,
    int sampleRate, {
    String? bookId,
  }) async {
    final previous = _files[(bookId, fingerprint)] ?? 0;
    _files[(bookId, fingerprint)] = pcm.length;
    if (bookId == null) {
      samplesBytes += pcm.length - previous;
    } else {
      _bytes[bookId] = (_bytes[bookId] ?? 0) + pcm.length - previous;
    }
    notifyListeners();
    return file(fingerprint, bookId: bookId)!;
  }

  @override
  int bytesForBook(String bookId) => _bytes[bookId] ?? 0;

  @override
  int get totalBytes => _bytes.values.fold(0, (a, b) => a + b) + samplesBytes;

  /// Подставное «записано на диск»: скачанный звук главы занимает место (настоящее хранилище считает файлы).
  void addBook(String bookId, int bytes) {
    if (bytes <= 0) return;
    _bytes[bookId] = (_bytes[bookId] ?? 0) + bytes;
    notifyListeners();
  }

  /// Подставное «записано на диск» для пробы голоса.
  void addSamples(int bytes) {
    if (bytes <= 0) return;
    samplesBytes += bytes;
    notifyListeners();
  }

  @override
  void removeBook(String bookId) {
    _files.removeWhere((key, _) => key.$1 == bookId);
    _bytes.remove(bookId);
    notifyListeners();
  }

  @override
  void clearAll() {
    _files.clear();
    _bytes.clear();
    samplesBytes = 0;
    notifyListeners();
  }
}

/// Удаление отменило публикацию. Это не ошибка синтеза и не повод его повторять.
class AudioWriteCancelled implements Exception {
  const AudioWriteCancelled();

  @override
  String toString() => 'Запись звука отменена удалением';
}
