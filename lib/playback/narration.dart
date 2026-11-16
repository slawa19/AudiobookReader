import 'package:flutter/foundation.dart';

import '../book/model.dart';
import '../library/library.dart';
import '../tts/segments.dart';
import '../tts/sentences.dart';

/// Состояния прослушивания — ровно таблица А§6.6, других нет.
enum NarrationState { idle, preparing, playing, waiting, paused, stopped }

enum StopReason { error, endOfBook }

/// Классы постоянных ошибок, которые экран показывает по-разному (FR-P6, FR-P7). [badKey] — отказ по ключу
/// (400/403 «API key not valid» и подобные): распознанная причина с кнопкой «Изменить ключ».
enum NarrationErrorKind { payment, modelNotFound, badKey, other }

@immutable
class NarrationError {
  const NarrationError(this.kind, this.googleMessage, {this.modelId});

  final NarrationErrorKind kind;

  /// Текст Google как есть — не переводится.
  final String googleMessage;

  /// Модель, на которой случилась ошибка (для 404): панель называет её, а не ту, что выбрана в настройках потом.
  final String? modelId;
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

/// Сохранённое место на странице, первое начинающееся на ней предложение или начало текущего.
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

/// Те же правила пригодности текста, что у синтеза, включая сноски и блоки из одних знаков.
int? spokenBlockFrom(Book book, int from, {required bool forward}) {
  var i = from;
  while (i >= 0 && i < book.blocks.length) {
    if (chapterSegments([book.blocks[i]]).isNotEmpty) return i;
    i += forward ? 1 : -1;
  }
  return null;
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

  /// Точное звучащее место: блок и смещение в нём.
  ReadingPosition? get sounding;

  /// Начало звучащей единицы (отрезка; в прототипе — блока или его части от выбранного предложения). Это и есть
  /// место прослушивания, которое контроллер сохраняет (А§4, А§5).
  ReadingPosition? get unitStart;

  double get speed;
  SleepTimer? get sleepTimer;
  DateTime now();

  /// «Активно» в смысле А§5: позицию пишет контроллер.
  bool get isActive => state != NarrationState.idle && state != NarrationState.stopped;

  /// Счётчик явных команд пользователя, которые запускают звук или меняют его место: «Слушать» (из `idle`, паузы,
  /// остановки), «Читать отсюда», «назад», «вперёд», выбор главы — откуда бы они ни пришли: с экрана, из
  /// уведомления, с гарнитуры. Экран включает следование за голосом, когда счётчик изменился (А§5, А§6.6).
  /// Автоматические переходы (следующий отрезок, конец главы, смена голоса или модели) его не меняют.
  int get commandRevision;

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
  /// `preparing`/`playing`/`waiting` — звучит с нового места; без сеанса или из `stopped` — новый сеанс. Перед
  /// каждым явным стартом истёкший таймер сна снимается (FR-D1).
  void readFrom(Book book, int block);

  /// Переход по оглавлению: если идёт сеанс этой книги — смена места с прежним намерением (А§5, А§6.6);
  /// без сеанса ничего не делает.
  void moveIfListening(Book book, int block);

  /// «Назад» и «вперёд» плеера — по абзацам (А§6.6): к началу следующего читаемого блока; к началу текущего,
  /// а из его начала — предыдущего. Намерение сохраняется.
  void next();
  void previous();

  /// «Закрыть» (FR-P8) или закрытие книги: сеанс завершается (`idle`), таймер сна снимается, затем
  /// [screenPosition] — место на экране — передаётся писателю позиции чтения; с этого момента её пишет экран (А§5).
  /// Место прослушивания при этом не забывается: с него продолжит следующее «Слушать», если оно на экране.
  void close({ReadingPosition? screenPosition});

  void setSpeed(double speed);

  /// Таймер сна (FR-D1). Снимается при срабатывании, «Закрыть», закрытии книги и смене книги; смена места, главы
  /// и голоса в той же книге его не снимает. Срок, истёкший без звука: на паузе — таймер просто снят; в
  /// `preparing`/`waiting` — пауза, и таймер снят.
  void setSleepTimer(SleepTimer? timer);

  /// Голос или модель действительно сменились: новый сеанс с начала текущего отрезка — в том числе стартового,
  /// начатого с предложения внутри блока, — с прежним намерением (FR-V2). Касание уже выбранного голоса или модели
  /// сюда не приходит (правило j).
  void restartSession();

  /// «Очистить озвучку» (FR-M3, А§4): сеанс завершается, «Скачать главу» останавливается, готовность глав и
  /// пробы сбрасываются, звук всех книг и проб удаляется. Одна операция.
  void clearAllNarration();

  /// «Удалить озвучку» книги (FR-D3, А§4).
  void deleteBookNarration(String bookId);

  /// Удаление книги (FR-L5, А§4): то же, что [deleteBookNarration], и папка книги с полки.
  void deleteBook(String bookId);
}
