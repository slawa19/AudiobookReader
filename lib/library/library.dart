import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../book/model.dart';

/// Позиция чтения (А§5): блок, смещение в нём, число знаков до блока.
@immutable
class ReadingPosition {
  const ReadingPosition(this.block, this.offset);

  final int block;
  final int offset;

  @override
  bool operator ==(Object other) => other is ReadingPosition && other.block == block && other.offset == offset;

  @override
  int get hashCode => Object.hash(block, offset);

  @override
  String toString() => 'ReadingPosition($block, $offset)';
}

/// Строка полки: всё, что нужно полке, без загрузки книги (А§4, `meta.json` + `state.json`).
class ShelfEntry {
  ShelfEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.lastOpened,
    this.cover,
    this.fraction,
    this.chapterTitle,
    required this.bookBytes,
  });

  final String id;
  final String title;
  final String author;
  final ImageProvider? cover;
  DateTime lastOpened;

  /// Доля прочитанного; `null` — книгу ещё не открывали («новая»).
  double? fraction;
  String? chapterTitle;

  /// Размер папки книги без озвучки, байт.
  final int bookBytes;
}

enum AddJobStatus { adding, failed }

/// Добавляемая книга или отказ добавления (FR-L2, FR-B2, FR-B6): строка на полке до «✕».
class AddJob {
  AddJob({required this.fileName, required this.status, this.error, this.technical});

  final String fileName;
  AddJobStatus status;
  String? error;
  String? technical;
}

/// Полка и хранение книг (А§2, `library`). Единственный писатель позиции и настроек книги.
abstract class Library extends ChangeNotifier {
  /// Книги по убыванию времени последнего открытия (FR-L4).
  List<ShelfEntry> get shelf;

  List<AddJob> get addJobs;

  ShelfEntry entry(String bookId);

  Future<Book> loadBook(String bookId);

  /// Размеры картинок книги — нужны разбивке на страницы до загрузки самих картинок.
  Map<String, Size> imageSizes(String bookId);

  ImageProvider image(String bookId, String imageId);

  ReadingPosition? positionOf(String bookId);

  void savePosition(String bookId, ReadingPosition position, {double? fraction, String? chapterTitle});

  void markOpened(String bookId);

  /// Свой голос книги; `null` — как в настройках (FR-V2).
  String? bookVoice(String bookId);

  void setBookVoice(String bookId, String? voice);

  void deleteBook(String bookId);

  void dismissAddJob(AddJob job);
}
