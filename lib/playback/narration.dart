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

/// Видимая страница: от [start] (включительно) до [end] (не включая) — блок и смещение.
@immutable
class PageRange {
  const PageRange(this.start, this.end);

  final ReadingPosition start;
  final ReadingPosition end;

  static bool _le(ReadingPosition a, ReadingPosition b) => a.block < b.block || (a.block == b.block && a.offset <= b.offset);

  bool contains(ReadingPosition p) => _le(start, p) && !_le(end, p);
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

  /// Начало звучащей единицы (отрезка; в прототипе — блока или его части от выбранного предложения). Это и есть
  /// место прослушивания, которое контроллер сохраняет (А§4, А§5).
  ReadingPosition? get unitStart;

  double get speed;
  SleepTimer? get sleepTimer;
  DateTime now();

  /// «Активно» в смысле А§5: позицию пишет контроллер.
  bool get isActive => state != NarrationState.idle && state != NarrationState.stopped;

  /// «Слушать» без сеанса (`idle`), FR-P3. Экран только сообщает видимую страницу [page]; место выбирает
  /// контроллер (замечание владельца 2026-11-14):
  /// 1. сохранённое место прослушивания стоит на этой странице — с него;
  /// 2. иначе — с первого предложения, которое начинается на странице (хвост предложения с прошлой страницы не
  ///    читается);
  /// 3. если на странице не начинается ни одно предложение — с начала того, внутри которого она лежит.
  /// Без ключа экран сюда не приходит (FR-P7).
  void listen(Book book, PageRange page);

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

  /// «Закрыть» (FR-P8) или закрытие книги: сеанс завершается (`idle`), затем [screenPosition] — место на экране —
  /// передаётся писателю позиции чтения; с этого момента её пишет экран (А§5). Место прослушивания при этом не
  /// забывается: с него продолжит следующее «Слушать», если оно на экране.
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
