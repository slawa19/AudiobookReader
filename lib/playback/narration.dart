import 'package:flutter/foundation.dart';

import '../book/model.dart';

/// Состояния прослушивания — ровно таблица А§6.6, других нет.
enum NarrationState { idle, preparing, playing, waiting, paused, stopped }

enum StopReason { error, endOfBook }

/// Классы постоянных ошибок, которые экран показывает по-разному (FR-P6, FR-P7).
enum NarrationErrorKind { payment, modelNotFound, other }

@immutable
class NarrationError {
  const NarrationError(this.kind, this.googleMessage);

  final NarrationErrorKind kind;

  /// Текст Google как есть.
  final String googleMessage;
}

enum SleepKind { minutes, endOfChapter }

/// Таймер сна принадлежит контроллеру, а не сеансу (А§6.6); минуты — по настенным часам с момента установки.
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

/// Единственное место, где сходятся очередь, плеер, сеанс и позиция (А§6.6). Экран подписан на него и ничего
/// не решает сам.
abstract class NarrationController extends ChangeNotifier {
  NarrationState get state;
  StopReason? get stopReason;
  NarrationError? get error;

  /// Книга текущего прослушивания.
  String? get bookId;

  /// Звучащий блок и доля проигранного в нём (для подсветки и следования за голосом, А§5).
  int? get block;
  double get blockProgress;

  double get speed;
  SleepTimer? get sleepTimer;
  DateTime now();

  /// «Активно» в смысле А§5: позицию пишет контроллер.
  bool get isActive => state != NarrationState.idle && state != NarrationState.stopped;

  /// «Слушать» с блока или «Читать отсюда» (FR-P3). Без ключа экран сюда не приходит (FR-P7).
  void start(Book book, int fromBlock);

  /// «Слушать» после паузы или остановки.
  void resume();
  void pause();
  void next();
  void previous();

  /// «Закрыть» (FR-P8) или закрытие книги: `idle`.
  void close();

  void setSpeed(double speed);
  void setSleepTimer(SleepTimer? timer);

  /// Смена голоса или модели: новый сеанс с текущего отрезка с прежним намерением (FR-V2).
  void restartSession();
}
