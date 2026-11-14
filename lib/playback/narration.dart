import 'package:flutter/foundation.dart';

import '../book/model.dart';
import '../library/library.dart';

/// Состояния прослушивания — ровно таблица А§6.6, других нет.
enum NarrationState { idle, preparing, playing, waiting, paused, stopped }

enum StopReason { error, endOfBook }

/// Классы постоянных ошибок, которые экран показывает по-разному (FR-P6, FR-P7).
enum NarrationErrorKind { payment, modelNotFound, other }

@immutable
class NarrationError {
  const NarrationError(this.kind, this.googleMessage);

  final NarrationErrorKind kind;

  /// Текст Google как есть — не переводится.
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
/// не решает сам: каждое действие пользователя — одна команда, а не последовательность вызовов.
///
/// Подставная реализация прототипа и настоящая (А§6.3–6.6) выполняют один и тот же контракт.
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

  /// «Слушать» без сеанса: новый сеанс с места [from] — первого озвучиваемого места на экране, в том числе
  /// хвоста абзаца, начатого на прошлой странице (FR-P3). Без ключа экран сюда не приходит (FR-P7).
  void listen(Book book, ReadingPosition from);

  /// «Слушать» в панели плеера: из `paused` — с места паузы; из `stopped` — новый сеанс с актуальной сохранённой
  /// позиции (её мог переписать экран после явного перемещения, А§5).
  void resume();

  void pause();

  /// «Читать отсюда» (FR-P3): смена места с прежним намерением. Из `paused` — пауза на новом месте; из
  /// `preparing`/`playing`/`waiting` — звучит с нового места; без сеанса или из `stopped` — новый сеанс.
  void readFrom(Book book, int block);

  /// Переход по оглавлению: если идёт сеанс этой книги — смена места с прежним намерением (А§5, А§6.6);
  /// без сеанса ничего не делает.
  void moveIfListening(Book book, int block);

  /// «Назад» и «вперёд» плеера — к началу предыдущего и следующего отрезка; намерение сохраняется.
  void next();
  void previous();

  /// «Закрыть» (FR-P8) или закрытие книги: сеанс завершается (`idle`), затем [screenPosition] — начало страницы
  /// на экране — передаётся писателю позиции. С этого момента позицию пишет экран (А§5).
  void close({ReadingPosition? screenPosition});

  void setSpeed(double speed);
  void setSleepTimer(SleepTimer? timer);

  /// Смена голоса или модели: новый сеанс с текущего отрезка с прежним намерением (FR-V2).
  void restartSession();

  /// «Очистить озвучку» (FR-M3, А§4): сеанс завершается, «Скачать главу» останавливается, готовность глав и
  /// пробы сбрасываются, звук всех книг и проб удаляется. Одна операция.
  void clearAllNarration();

  /// «Удалить озвучку» книги (FR-D3, А§4).
  void deleteBookNarration(String bookId);

  /// Удаление книги (FR-L5, А§4): то же, что [deleteBookNarration], и папка книги с полки.
  void deleteBook(String bookId);
}
