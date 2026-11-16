import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../book/model.dart';
import 'library.dart';

/// Подставная полка прототипа: несколько книг, две из них с настоящим текстом из assets/demo/.
/// Ничего не пишет на диск и никуда не ходит. В настоящем приложении её заменит `Library` на файлах (А§4).
class FakeLibrary extends Library {
  FakeLibrary({DateTime? now}) : _now = now ?? DateTime(2026, 11, 14, 12, 30) {
    _entries.addAll(_demoEntries(_now));
    _positions['kapitanskaya'] = const ReadingPosition(39, 0);
    _positions['dama'] = const ReadingPosition(40, 0);
    _finished.add('dushi');
  }

  final DateTime _now;
  final List<ShelfEntry> _entries = [];
  final List<AddJob> _jobs = [];
  final Map<String, ReadingPosition> _positions = {};
  final Map<String, String?> _bookVoices = {};
  final Map<String, Book> _books = {};

  /// «Пустая полка» для показа (только прототип).
  bool demoEmptyShelf = false;

  static const _textAssets = {'kapitanskaya': 'assets/demo/kapitanskaya.json', 'dama': 'assets/demo/dama.json'};

  /// Загружает тексты заранее, чтобы открытие книги было мгновенным (и тесты не ждали платформу).
  Future<void> preload() async {
    for (final e in _textAssets.entries) {
      final data = await rootBundle.load(e.value);
      final json = jsonDecode(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      _books[e.key] = Book.fromJson(json as Map<String, Object?>);
    }
    for (final entry in _entries) {
      final book = _books[entry.id];
      final pos = _positions[entry.id];
      if (book != null && pos != null) {
        entry.fraction = book.fractionAt(pos.block, pos.offset);
        entry.chapterTitle = chapterLabel(book, book.chapterOf(pos.block));
      }
    }
  }

  @override
  List<ShelfEntry> get shelf {
    if (demoEmptyShelf) return const [];
    final opened = _entries.where((e) => e.opened).toList()..sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
    final fresh = _entries.where((e) => !e.opened).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return [...opened, ...fresh];
  }

  @override
  List<AddJob> get addJobs => List.unmodifiable(_jobs);

  @override
  void recordFileFailure(String fileName, Object error) {
    _jobs.insert(0, AddJob(fileName: fileName, status: AddJobStatus.failed,
        failure: AddFailure.unreadable, technical: error.toString()));
    notifyListeners();
  }

  @override
  ShelfEntry entry(String bookId) => _entries.firstWhere((e) => e.id == bookId);

  Book? cachedBook(String bookId) => _books[bookId] ?? (_entries.any((e) => e.id == bookId) ? _stub(bookId) : null);

  @override
  Future<Book> loadBook(String bookId) async {
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    return cachedBook(bookId)!;
  }

  /// Задержка открытия книги — как чтение `book.json` с диска (для теста двойного нажатия).
  Duration loadDelay = Duration.zero;

  @override
  Map<String, Size> imageSizes(String bookId) => const {'steppe': Size(960, 600)};

  @override
  ImageProvider image(String bookId, String imageId) => AssetImage('assets/demo/images/$imageId.png');

  @override
  ReadingPosition? positionOf(String bookId) => _positions[bookId];

  /// В настоящей библиотеке — `state.json` рядом с позицией чтения; в прототипе — память.
  final Map<String, ReadingPosition> _listening = {};

  @override
  ReadingPosition? listeningPositionOf(String bookId) => _listening[bookId];

  @override
  void saveListeningPosition(String bookId, ReadingPosition position) => _listening[bookId] = position;

  /// Дочитанные книги (FR-L4) — отдельный факт; в приложении — в `state.json`.
  final Set<String> _finished = {};

  @override
  bool isFinished(String bookId) => _finished.contains(bookId);

  @override
  void setFinished(String bookId, bool finished) {
    if (_finished.contains(bookId) == finished) return;
    finished ? _finished.add(bookId) : _finished.remove(bookId);
    final e = _entries.where((e) => e.id == bookId).firstOrNull;
    final book = _books[bookId];
    final pos = _positions[bookId];
    if (e != null) {
      if (finished) {
        e.fraction = 1;
      } else if (book != null && pos != null) {
        e.fraction = book.fractionAt(pos.block, pos.offset);
      }
    }
    notifyListeners();
  }

  @override
  void savePosition(String bookId, ReadingPosition position, {double? fraction}) {
    if (_positions[bookId] == position) return;
    _positions[bookId] = position;
    final e = _entries.where((e) => e.id == bookId).firstOrNull;
    final book = _books[bookId];
    if (e != null) {
      final f = fraction ?? book?.fractionAt(position.block, position.offset);
      if (_finished.contains(bookId)) {
        e.fraction = 1;
      } else if (f != null) {
        e.fraction = f;
      }
      if (book != null) e.chapterTitle = chapterLabel(book, book.chapterOf(position.block));
    }
    notifyListeners();
  }

  @override
  void markOpened(String bookId) {
    final e = entry(bookId);
    final last = _entries.map((e) => e.lastOpened).whereType<DateTime>().fold<DateTime>(_now, (a, b) => b.isAfter(a) ? b : a);
    final now = DateTime.now();
    e.lastOpened = now.isAfter(last) ? now : last.add(const Duration(minutes: 1));
    e.fraction ??= 0;
    notifyListeners();
  }

  @override
  String? bookVoice(String bookId) => _bookVoices[bookId];

  @override
  void setBookVoice(String bookId, String? voice) {
    _bookVoices[bookId] = voice;
    notifyListeners();
  }

  @override
  Future<void> deleteBook(String bookId) async {
    _entries.removeWhere((e) => e.id == bookId);
    _positions.remove(bookId);
    _listening.remove(bookId);
    _finished.remove(bookId);
    _bookVoices.remove(bookId);
    notifyListeners();
  }

  @override
  void dismissAddJob(AddJob job) {
    _jobs.remove(job);
    notifyListeners();
  }

  // --- имитация добавления (системного выбора файла в прототипе нет) ---------------------------------

  /// Файлы, которые «выбирает» имитация системного окна выбора файла.
  static const demoFiles = <({String name, String kind})>[
    (name: 'turgenev_zapiski_ohotnika.fb2', kind: 'duplicate'),
    (name: 'pushkin_povesti_belkina.fb2.zip', kind: 'ok'),
    (name: 'scan_2019.pdf', kind: 'unsupported'),
    (name: 'rasskazy.fb2', kind: 'broken'),
    (name: 'bestseller.epub', kind: 'drm'),
  ];

  /// Книги, которые получаются из «файлов» имитации выбора (id — как первые знаки sha256 у настоящей, А§4).
  static final _demoFileBooks = <String, ShelfEntry Function(DateTime addedAt)>{
    'duplicate': (at) => ShelfEntry(
        id: 'zapiski', title: 'Записки охотника', author: 'Иван Тургенев', addedAt: at, bookBytes: 1300 * 1024),
    'ok': (at) => ShelfEntry(
        id: 'belkin', title: 'Повести Белкина', author: 'Александр Пушкин', addedAt: at, bookBytes: 410 * 1024),
  };

  /// Возвращает id имеющейся книги, если файл уже на полке (FR-L3); иначе начинает добавление. Тот же файл,
  /// который уже добавляется, второй раз не добавляется. Удалённая книга добавляется заново.
  String? addDemoFile(String name, String kind) {
    final make = _demoFileBooks[kind];
    if (make != null) {
      final id = make(_now).id;
      if (_entries.any((e) => e.id == id)) return id;
    }
    if (_jobs.any((j) => j.fileName == name && j.status == AddJobStatus.adding)) return null;
    final job = AddJob(fileName: name, status: AddJobStatus.adding);
    _jobs.insert(0, job);
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (!_jobs.contains(job)) return;
      if (make != null) {
        _jobs.remove(job);
        final entry = make(DateTime.now());
        if (!_entries.any((e) => e.id == entry.id)) _entries.add(entry);
      } else {
        _fail(job, kind);
      }
      notifyListeners();
    });
    return null;
  }

  /// Показывает строку добавления в заданном состоянии сразу, без ожидания (панель «Состояния для показа»).
  void demoAddJob(String kind) {
    final names = {
      'adding': 'tolstoy_voyna_i_mir.fb2.zip',
      'unsupported': 'scan_2019.pdf',
      'broken': 'rasskazy.fb2',
      'drm': 'bestseller.epub',
    };
    final job = AddJob(fileName: names[kind]!, status: AddJobStatus.adding);
    if (kind != 'adding') _fail(job, kind);
    _jobs.insert(0, job);
    notifyListeners();
  }

  void clearAddJobs() {
    _jobs.clear();
    notifyListeners();
  }

  void _fail(AddJob job, String kind) {
    job.status = AddJobStatus.failed;
    switch (kind) {
      case 'unsupported':
        job.failure = AddFailure.unsupported;
      case 'broken':
        job.failure = AddFailure.unreadable;
        job.technical = 'XML: unexpected end of file, line 1204';
      case 'drm':
        job.failure = AddFailure.protected;
    }
  }

  void setDemoEmptyShelf(bool value) {
    demoEmptyShelf = value;
    notifyListeners();
  }

  Book _stub(String bookId) {
    final e = entry(bookId);
    return _books[bookId] = Book(
      id: bookId,
      title: e.title,
      author: e.author,
      language: 'ru',
      chapters: const [Chapter(title: 'О прототипе', level: 1, firstBlock: 0, blockCount: 3)],
      blocks: [
        Block(index: 0, kind: BlockKind.heading, text: e.title),
        Block(index: 1, kind: BlockKind.paragraph, text: '${e.author}.'),
        const Block(
          index: 2,
          kind: BlockKind.paragraph,
          text: 'Текста этой книги в прототипе нет — она стоит на полке, чтобы полка выглядела как настоящая. '
              'Полный текст есть у «Капитанской дочки» и у сборника «Дама с собачкой. Рассказы».',
        ),
      ],
      notes: const {},
    );
  }

  static List<ShelfEntry> _demoEntries(DateTime now) {
    // [hoursAgo] — когда открывали; `null` — ни разу (книга «новая»).
    ShelfEntry e(String id, String title, String author, int? hoursAgo,
            {bool cover = true, double? fraction, int kb = 600, int addedDaysAgo = 60}) =>
        ShelfEntry(
          id: id,
          title: title,
          author: author,
          addedAt: now.subtract(Duration(days: addedDaysAgo)),
          lastOpened: hoursAgo == null ? null : now.subtract(Duration(hours: hoursAgo)),
          cover: cover ? AssetImage('assets/demo/covers/$id.png') : null,
          fraction: fraction,
          bookBytes: kb * 1024,
        );
    return [
      e('kapitanskaya', 'Капитанская дочка', 'Александр Пушкин', 1, kb: 480),
      e('dama', 'Дама с собачкой. Рассказы', 'Антон Чехов', 30, kb: 520),
      e('voyna', 'Война и мир', 'Лев Толстой', null, kb: 5800, addedDaysAgo: 8),
      e('zapiski', 'Записки охотника', 'Иван Тургенев', 260, cover: false, fraction: 0.58, kb: 1300),
      e('geroy', 'Герой нашего времени', 'Михаил Лермонтов', 400, fraction: 0.03, kb: 700),
      e('dushi', 'Мёртвые души', 'Николай Гоголь', 900, fraction: 1, kb: 1900),
    ];
  }
}
