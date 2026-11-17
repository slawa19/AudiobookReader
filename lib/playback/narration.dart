import 'package:flutter/foundation.dart';

import '../book/model.dart';
import '../library/library.dart';
import '../tts/segments.dart';
import '../tts/sentences.dart';

/// The listening states are exactly the table of А§6.6, there are no others.
enum NarrationState { idle, preparing, playing, waiting, paused, stopped }

enum StopReason { error, endOfBook }

/// Classes of permanent errors that the screen shows differently (FR-P6, FR-P7). [badKey] — a key rejection
/// (400/403 "API key not valid" and the like): a recognized cause with the "Change key" button.
enum NarrationErrorKind { payment, modelNotFound, badKey, other }

@immutable
class NarrationError {
  const NarrationError(this.kind, this.googleMessage, {this.modelId});

  final NarrationErrorKind kind;

  /// Google's text as is — not translated.
  final String googleMessage;

  /// The model on which the error happened (for 404): the panel names it, not the one selected in settings afterwards.
  final String? modelId;
}

/// The visible page: from [start] (inclusive) to [end] (exclusive) — a block and an offset.
@immutable
class PageRange {
  const PageRange(this.start, this.end);

  final ReadingPosition start;
  final ReadingPosition end;

  static bool _le(ReadingPosition a, ReadingPosition b) => a.block < b.block || (a.block == b.block && a.offset <= b.offset);

  bool contains(ReadingPosition p) => _le(start, p) && !_le(end, p);
}

/// The saved place on the page, the first sentence starting on it, or the start of the current one.
ReadingPosition listenStart(Book book, PageRange page, ReadingPosition? saved) {
  if (saved != null && page.contains(saved)) return saved;
  for (var i = page.start.block; i <= page.end.block && i < book.blocks.length; i++) {
    final block = book.blocks[i];
    if (!block.isSpoken) continue;
    for (final offset in blockSentenceStarts(block)) {
      final position = ReadingPosition(i, offset);
      if (page.contains(position)) return position;
    }
  }
  final block = book.blocks[page.start.block];
  return ReadingPosition(block.index, blockSentenceStartAt(block, page.start.offset));
}

/// The same text suitability rules as in synthesis, including footnotes and blocks of nothing but marks.
int? spokenBlockFrom(Book book, int from, {required bool forward}) {
  var i = from;
  while (i >= 0 && i < book.blocks.length) {
    if (chapterSegments([book.blocks[i]]).isNotEmpty) return i;
    i += forward ? 1 : -1;
  }
  return null;
}

enum SleepKind { minutes, endOfChapter }

/// The sleep timer belongs to the controller, not the session (А§6.6); minutes — by the wall clock since it was set.
@immutable
class SleepTimer {
  const SleepTimer.minutes(this.minutes, this.setAt) : kind = SleepKind.minutes;
  const SleepTimer.endOfChapter(this.setAt)
      : kind = SleepKind.endOfChapter,
        minutes = 0;

  final SleepKind kind;
  final int minutes;
  final DateTime setAt;

  Duration remaining(DateTime now) {
    final left = setAt.add(Duration(minutes: minutes)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// The single place where the queue, player, session and position meet (А§6.6). The screen subscribes to it and decides
/// nothing itself: every user action is one command, not a sequence of calls.
///
/// The prototype's fake implementation and the real one (А§6.3–6.6) fulfill the same contract.
abstract class NarrationController extends ChangeNotifier {
  NarrationState get state;
  StopReason? get stopReason;
  NarrationError? get error;

  /// The book of the current listening.
  String? get bookId;

  /// The voiced block and the fraction played in it (for highlighting and following the voice, А§5).
  int? get block;
  double get blockProgress;

  /// The exact voiced place: a block and an offset in it.
  ReadingPosition? get sounding;

  /// The start of the voiced unit (a segment; in the prototype — a block or its part from the chosen sentence). This is
  /// the listening place that the controller saves (А§4, А§5).
  ReadingPosition? get unitStart;

  double get speed;
  SleepTimer? get sleepTimer;
  DateTime now();

  /// "Active" in the sense of А§5: the controller writes the position.
  bool get isActive => state != NarrationState.idle && state != NarrationState.stopped;

  /// A counter of explicit user commands that start audio or change its place: "Listen" (from `idle`, a pause,
  /// a stop), "Read from here", "back", "forward", chapter selection — wherever they come from: the screen, the
  /// notification, the headset. The screen turns following the voice on when the counter changed (А§5, А§6.6).
  /// Automatic transitions (the next segment, end of chapter, a voice or model change) do not change it.
  int get commandRevision;

  /// "Listen" without a session (`idle`), FR-P3. The screen only reports the visible page [page]; the place is chosen
  /// by the controller (owner's remark 2026-11-14):
  /// 1. the saved listening place is on this page — from it;
  /// 2. otherwise — from the first sentence that starts on the page (the tail of a sentence from the previous page
  ///    is not read);
  /// 3. if no sentence starts on the page — from the start of the one inside which it lies.
  /// Without a key the screen does not come here (FR-P7).
  void listen(Book book, PageRange page);

  /// "Listen" in the player panel: from `paused` — from the pause place; from `stopped` — a new session from the
  /// current saved position (the screen may have rewritten it after an explicit move, А§5).
  void resume();

  void pause();

  /// "Read from here" (FR-P3): a place change with the previous intent. From `paused` — paused at the new place; from
  /// `preparing`/`playing`/`waiting` — plays from the new place; without a session or from `stopped` — a new session.
  /// Before every explicit start an expired sleep timer is cleared (FR-D1).
  void readFrom(Book book, int block);

  /// Navigation via the table of contents: if a session of this book is running — a place change with the previous
  /// intent (А§5, А§6.6); without a session it does nothing.
  void moveIfListening(Book book, int block);

  /// The player's "Back" and "forward" — by paragraphs (А§6.6): to the start of the next readable block; to the start
  /// of the current one, and from its start — of the previous one. The intent is kept.
  void next();
  void previous();

  /// "Close" (FR-P8) or closing the book: the session ends (`idle`), the sleep timer is cleared, then
  /// [screenPosition] — the place on the screen — is passed to the reading-position writer; from then on the screen
  /// writes it (А§5). The listening place is not forgotten in this: the next "Listen" continues from it if it is on the
  /// screen.
  void close({ReadingPosition? screenPosition});

  void setSpeed(double speed);

  /// The sleep timer (FR-D1). Cleared when it fires, on "Close", on closing the book and on changing the book; a change
  /// of place, chapter and voice in the same book does not clear it. A deadline that expired without audio: on a pause
  /// — the timer is simply cleared; in `preparing`/`waiting` — a pause, and the timer is cleared.
  void setSleepTimer(SleepTimer? timer);

  /// The voice or model actually changed: a new session from the start of the current segment — including a start one
  /// begun from a sentence inside a block — with the previous intent (FR-V2). Touching the already chosen voice or
  /// model does not come here (rule j).
  void restartSession();

  /// "Clear narration" (FR-M3, А§4): the session ends, "Download chapter" stops, chapter readiness and
  /// probes are reset, the audio of all books and probes is deleted. One operation.
  void clearAllNarration();

  /// "Delete narration" of a book (FR-D3, А§4).
  void deleteBookNarration(String bookId);

  /// Deleting a book (FR-L5, А§4): the same as [deleteBookNarration], plus the book folder from the shelf.
  void deleteBook(String bookId);
}
