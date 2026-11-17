import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../book/model.dart';
import 'usage.dart';

export 'usage.dart';

/// Reading position (А§5): block, offset in it, number of characters before the block.
@immutable
class ReadingPosition {
  const ReadingPosition(
    this.block,
    this.offset, {
    this.charsBefore = 0,
    this.anchorText = '',
  });

  final int block;
  final int offset;
  final int charsBefore;
  final String anchorText;

  Map<String, Object?> toJson() => {
    'block': block,
    'offset': offset,
    'charsBefore': charsBefore,
    'anchorText': anchorText,
  };

  factory ReadingPosition.fromJson(Map<String, Object?> json) =>
      ReadingPosition(
        json['block']! as int,
        json['offset']! as int,
        charsBefore: json['charsBefore']! as int,
        anchorText: json['anchorText']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.block == block &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(block, offset);

  @override
  String toString() => 'ReadingPosition($block, $offset)';
}

/// A shelf row: everything the shelf needs without loading the book (А§4, `meta.json` + `state.json`).
class ShelfEntry {
  ShelfEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.addedAt,
    this.lastOpened,
    this.cover,
    this.fraction,
    this.chapterTitle,
    required this.bookBytes,
  });

  final String id;
  final String title;
  final String author;
  final ImageProvider? cover;
  final DateTime addedAt;

  /// Time of the last opening; `null` — the book was never opened ("new"): it has no "Continue" card.
  DateTime? lastOpened;

  bool get opened => lastOpened != null;

  /// Fraction read; `null` — the book has not been opened yet. 1 — finished (FR-L4).
  double? fraction;
  String? chapterTitle;

  /// Size of the book folder without narration, in bytes.
  final int bookBytes;
}

enum AddJobStatus { adding, failed }

/// The reason an add was rejected (FR-B2, FR-B6). The text in the interface language is provided by the screen.
/// [unreadable] — including a file from which not a single block could be obtained: an empty book never
/// reaches the reading screen.
enum AddFailure { unsupported, unreadable, protected }

/// A book being added or an add failure (FR-L2, FR-B2, FR-B6): a row on the shelf until "✕".
class AddJob {
  AddJob({
    required this.fileName,
    required this.status,
    this.failure,
    this.technical,
  });

  final String fileName;
  AddJobStatus status;
  AddFailure? failure;

  /// The technical reason as is (the parser's message), not translated.
  String? technical;
}

/// The shelf and book storage (А§2, `library`). The only writer of a book's position and settings.
abstract class Library extends ChangeNotifier {
  /// A usage snapshot: local month start → model identifier → tokens.
  /// Immutable; in the file library available after ready.
  Map<DateTime, Map<String, UsageTokens>> get usage => const {};

  /// One paid response, including an error with usage. Uniqueness of the response
  /// is ensured by the queue. The Future completes after the atomic write to disk.
  /// [at] — the moment of the response; without it the library's injected clock is used.
  Future<void> recordUsage({
    required String modelId,
    required int audioTokens,
    required int inputTokens,
    DateTime? at,
  }) async =>
      throw UnsupportedError('Recording usage is not implemented in this library');

  /// Returns a ready or already existing book; on failure — null and a row in [addJobs].
  /// The caller keeps the file at [path] until the Future completes, then deletes its own copy.
  Future<ShelfEntry?> addFile(String path, String fileName) async =>
      throw UnsupportedError(
        'Adding a file is not implemented in this library',
      );

  /// A file operation error is visible on the shelf until the user explicitly closes the row.
  void recordFileFailure(String fileName, Object error);

  /// Writes the latest changes immediately and waits for the writer. Before background, pause and closing.
  Future<void> flush() async {}

  /// The shelf (FR-L4): first the books that were opened, by descending time of last opening, then the never-
  /// opened ones — new on top. The screen puts the first opened book into the "Continue" card, and the unopened ones at
  /// the start of the list below it.
  List<ShelfEntry> get shelf;

  List<AddJob> get addJobs;

  ShelfEntry entry(String bookId);

  Future<Book> loadBook(String bookId);

  /// Image sizes of the book — pagination needs them before the images themselves are loaded.
  Map<String, Size> imageSizes(String bookId);

  ImageProvider image(String bookId, String imageId);

  /// Reading position (А§5): the start of the first line on screen or, while narration is active, the place being
  /// voiced.
  ReadingPosition? positionOf(String bookId);

  /// Writes the reading position and computes the chapter label from the book. The prototype takes a fraction from the
  /// screen, including 1 on the last page. For a finished book the fraction on the shelf is 1 at any position.
  void savePosition(
    String bookId,
    ReadingPosition position, {
    double? fraction,
  });

  /// "Finished" (FR-L4, `state.json`) is a separate fact, not derived from the position. It is set by showing the last
  /// page (including the first layout of a single-page book) and by the end of listening; it is cleared only by showing
  /// a page earlier than the last.
  bool isFinished(String bookId);

  void setFinished(String bookId, bool finished);

  /// The listening place (А§4, `state.json`): the start of the last unit that was voiced. Stored separately from the
  /// reading position and not forgotten on pause, stop and "Close" — "Listen" continues from it (FR-P3).
  ReadingPosition? listeningPositionOf(String bookId);

  void saveListeningPosition(String bookId, ReadingPosition position);

  void markOpened(String bookId);

  /// The book's own voice; `null` — as in the settings (FR-V2).
  String? bookVoice(String bookId);

  void setBookVoice(String bookId, String? voice);

  Future<void> deleteBook(String bookId);

  void dismissAddJob(AddJob job);
}
