import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../book/model.dart';
import 'usage.dart';

export 'usage.dart';

/// Позиция чтения (А§5): блок, смещение в нём, число знаков до блока.
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

/// Строка полки: всё, что нужно полке, без загрузки книги (А§4, `meta.json` + `state.json`).
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

  /// Время последнего открытия; `null` — книгу ни разу не открывали («новая»): карточки «Продолжить» у неё нет.
  DateTime? lastOpened;

  bool get opened => lastOpened != null;

  /// Доля прочитанного; `null` — книгу ещё не открывали. 1 — дочитана (FR-L4).
  double? fraction;
  String? chapterTitle;

  /// Размер папки книги без озвучки, байт.
  final int bookBytes;
}

enum AddJobStatus { adding, failed }

/// Причина отказа добавления (FR-B2, FR-B6). Текст на языке интерфейса даёт экран.
/// [unreadable] — в том числе файл, из которого не получилось ни одного блока: пустая книга до экрана чтения
/// не доходит.
enum AddFailure { unsupported, unreadable, protected }

/// Добавляемая книга или отказ добавления (FR-L2, FR-B2, FR-B6): строка на полке до «✕».
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

  /// Техническая причина как есть (сообщение разборщика), не переводится.
  String? technical;
}

/// Полка и хранение книг (А§2, `library`). Единственный писатель позиции и настроек книги.
abstract class Library extends ChangeNotifier {
  /// Снимок расхода: местное начало месяца → идентификатор модели → токены.
  /// Неизменяемый; в файловой библиотеке доступен после ready.
  Map<DateTime, Map<String, UsageTokens>> get usage => const {};

  /// Один оплаченный ответ, в том числе ошибка с usage. Уникальность ответа
  /// обеспечивает очередь. Future завершается после атомарной записи на диск.
  /// [at] — момент ответа, без него используются подставляемые часы библиотеки.
  Future<void> recordUsage({
    required String modelId,
    required int audioTokens,
    required int inputTokens,
    DateTime? at,
  }) async =>
      throw UnsupportedError('Запись расхода в этой библиотеке не реализована');

  /// Возвращает готовую или уже имеющуюся книгу; при отказе — null и строку в [addJobs].
  /// Вызывающий сохраняет файл по [path] до завершения Future, затем удаляет свою копию.
  Future<ShelfEntry?> addFile(String path, String fileName) async =>
      throw UnsupportedError(
        'Добавление файла в этой библиотеке не реализовано',
      );

  /// Ошибка файловой операции видна на полке до явного закрытия строки пользователем.
  void recordFileFailure(String fileName, Object error);

  /// Записывает последние изменения немедленно и дожидается писателя. Перед фоном, паузой и закрытием.
  Future<void> flush() async {}

  /// Полка (FR-L4): сначала открывавшиеся книги по убыванию времени последнего открытия, затем ни разу не
  /// открытые — новые сверху. Экран ставит первую открывавшуюся в карточку «Продолжить», а неоткрытые — в
  /// начало списка под ней.
  List<ShelfEntry> get shelf;

  List<AddJob> get addJobs;

  ShelfEntry entry(String bookId);

  Future<Book> loadBook(String bookId);

  /// Размеры картинок книги — нужны разбивке на страницы до загрузки самих картинок.
  Map<String, Size> imageSizes(String bookId);

  ImageProvider image(String bookId, String imageId);

  /// Позиция чтения (А§5): начало первой строки на экране либо, пока озвучка активна, звучащее место.
  ReadingPosition? positionOf(String bookId);

  /// Записывает позицию чтения. Долю и название главы для полки библиотека считает сама по книге, если их не
  /// передали: писатель позиции (экран или контроллер) их знать не обязан. У дочитанной книги доля на полке — 1,
  /// какую бы позицию ни записали.
  void savePosition(
    String bookId,
    ReadingPosition position, {
    double? fraction,
    String? chapterTitle,
  });

  /// «Дочитана» (FR-L4, `state.json`) — отдельный факт, а не производная от позиции. Ставят показ последней
  /// страницы (в том числе первой раскладкой одностраничной книги) и конец прослушивания; снимает только показ
  /// страницы раньше последней.
  bool isFinished(String bookId);

  void setFinished(String bookId, bool finished);

  /// Место прослушивания (А§4, `state.json`): начало последней звучавшей единицы. Хранится отдельно от позиции
  /// чтения и не забывается при паузе, остановке и «Закрыть» — с него продолжает «Слушать» (FR-P3).
  ReadingPosition? listeningPositionOf(String bookId);

  void saveListeningPosition(String bookId, ReadingPosition position);

  void markOpened(String bookId);

  /// Свой голос книги; `null` — как в настройках (FR-V2).
  String? bookVoice(String bookId);

  void setBookVoice(String bookId, String? voice);

  Future<void> deleteBook(String bookId);

  void dismissAddJob(AddJob job);
}
