import 'dart:io';

import 'package:flutter/foundation.dart';

// Storage for the audio of segments and probes (ARCHITECTURE.md, section 6.5). Screens only need the space used from
// here; only `playback` deletes audio (A§2, A§4).

abstract class AudioStore extends ChangeNotifier {
  String get formatId;

  /// Without bookId — a shared voice probe, with bookId — a book segment.
  bool has(String fingerprint, {String? bookId});

  /// Only a finished file; missing audio is null.
  File? file(String fingerprint, {String? bookId});

  /// The PCM is not modified and stays with the queue so the write can be retried without new synthesis.
  /// Deletion during a write ends it with an AudioWriteCancelled error.
  Future<File> put(
    String fingerprint,
    Uint8List pcm,
    int sampleRate, {
    String? bookId,
  });

  /// Bytes of narration for one book.
  int bytesForBook(String bookId);

  /// Bytes of narration for all books and probes.
  int get totalBytes;

  void removeBook(String bookId);

  /// Audio of all books and probes.
  void clearAll();
}

/// The prototype's fake storage: numbers, not files.
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

  /// Fake "written to disk": downloaded chapter audio takes up space (the real storage counts files).
  void addBook(String bookId, int bytes) {
    if (bytes <= 0) return;
    _bytes[bookId] = (_bytes[bookId] ?? 0) + bytes;
    notifyListeners();
  }

  /// Fake "written to disk" for a voice probe.
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

/// Deletion cancelled the publication. This is not a synthesis error and no reason to retry it.
class AudioWriteCancelled implements Exception {
  const AudioWriteCancelled();

  @override
  String toString() => 'Audio write cancelled by deletion';
}
