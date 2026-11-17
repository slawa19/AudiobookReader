import 'dart:io';
import 'dart:typed_data';

import 'audio_encoder.dart';
import 'audio_store.dart';

/// One instance per root. Created after the library is ready, which cleans tmp/.
/// Short synchronous publish and delete operations are not separated by an await:
/// a delete command in the same isolate cannot wedge in between the check and the rename.
class FileAudioStore extends AudioStore {
  FileAudioStore(this.root, {required this.encoder}) {
    _component(encoder.extension);
    // Clean up only our own leftovers: tmp/ is shared with book adding.
    if (_temporary.existsSync()) _temporary.deleteSync(recursive: true);
  }

  final Directory root;
  final AudioEncoder encoder;
  int _generation = 0;
  final Map<String, int> _bookGenerations = {};

  Directory get _temporary => Directory('${root.path}/tmp/audio');
  Directory _book(String id) =>
      Directory('${root.path}/books/${_component(id)}');
  Directory _audio(String? id) => Directory(
    id == null ? '${root.path}/samples' : '${_book(id).path}/audio',
  );

  static String _component(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'component', 'Invalid path component');
    }
    return value;
  }

  File _target(String fingerprint, String? bookId) => File(
    '${_audio(bookId).path}/${_component(fingerprint)}.${encoder.extension}',
  );

  @override
  String get formatId => encoder.formatId;

  @override
  bool has(String fingerprint, {String? bookId}) =>
      file(fingerprint, bookId: bookId) != null;

  @override
  File? file(String fingerprint, {String? bookId}) {
    final target = _target(fingerprint, bookId);
    return target.existsSync() && target.lengthSync() > 0 ? target : null;
  }

  @override
  Future<File> put(
    String fingerprint,
    Uint8List pcm,
    int sampleRate, {
    String? bookId,
  }) async {
    final target = _target(fingerprint, bookId);
    if (sampleRate <= 0 || pcm.isEmpty || pcm.length.isOdd) {
      throw ArgumentError(
        'Expected non-empty 16-bit mono PCM with a positive sample rate',
      );
    }
    final generation = _generation;
    final bookGeneration = _bookGenerations[bookId] ?? 0;
    if (bookId != null && !_book(bookId).existsSync()) {
      throw const AudioWriteCancelled();
    }
    _temporary.createSync(recursive: true);
    final work = _temporary.createTempSync('write-');
    try {
      final input = File('${work.path}/input.pcm');
      final output = File('${work.path}/encoded.${encoder.extension}');
      await input.writeAsBytes(pcm, flush: true);
      await encoder.encode(
        pcmPath: input.path,
        outputPath: output.path,
        sampleRate: sampleRate,
      );
      if (generation != _generation ||
          bookGeneration != (_bookGenerations[bookId] ?? 0) ||
          (bookId != null && !_book(bookId).existsSync())) {
        throw const AudioWriteCancelled();
      }
      if (!output.existsSync() || output.lengthSync() == 0) {
        throw const FileSystemException('Кодировщик не создал звук');
      }
      // For a book — audio/ only, never create a missing books/<id>/.
      _audio(bookId).createSync();
      output.renameSync(target.path);
      notifyListeners();
      return target;
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  static int _bytes(Directory directory) => !directory.existsSync()
      ? 0
      : directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .fold(0, (sum, file) => sum + file.lengthSync());

  @override
  int bytesForBook(String bookId) => _bytes(_audio(bookId));

  Iterable<Directory> get _books {
    final books = Directory('${root.path}/books');
    return books.existsSync()
        ? books.listSync(followLinks: false).whereType<Directory>()
        : [];
  }

  @override
  int get totalBytes =>
      _bytes(_audio(null)) +
      _books.fold(
        0,
        (sum, book) => sum + _bytes(Directory('${book.path}/audio')),
      );

  static void _delete(Directory directory) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  @override
  void removeBook(String bookId) {
    _component(bookId);
    _bookGenerations[bookId] = (_bookGenerations[bookId] ?? 0) + 1;
    _delete(_audio(bookId));
    notifyListeners();
  }

  @override
  void clearAll() {
    _generation++;
    for (final book in _books) {
      _delete(Directory('${book.path}/audio'));
    }
    _delete(_audio(null));
    notifyListeners();
  }
}
