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
        entry.chapterTitle = _chapterLabel(book, pos.block);
      }
    }
  }

  @override
  List<ShelfEntry> get shelf {
    if (demoEmptyShelf) return const [];
    return [..._entries]..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
  }

  @override
  List<AddJob> get addJobs => List.unmodifiable(_jobs);

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

  @override
  void savePosition(String bookId, ReadingPosition position, {double? fraction, String? chapterTitle}) {
    if (_positions[bookId] == position) return;
    _positions[bookId] = position;
    final e = _entries.where((e) => e.id == bookId).firstOrNull;
    if (e != null) {
      if (fraction != null) e.fraction = fraction;
      if (chapterTitle != null) e.chapterTitle = chapterTitle;
    }
    notifyListeners();
  }

  @override
  void markOpened(String bookId) {
    final e = entry(bookId);
    e.lastOpened = DateTime.now().isAfter(_now) ? DateTime.now() : _now.add(const Duration(minutes: 1));
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
  void deleteBook(String bookId) {
    _entries.removeWhere((e) => e.id == bookId);
    _positions.remove(bookId);
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

  /// Возвращает id имеющейся книги, если файл уже на полке (FR-L3); иначе начинает добавление.
  String? addDemoFile(String name, String kind) {
    if (kind == 'duplicate') return 'zapiski';
    final job = AddJob(fileName: name, status: AddJobStatus.adding);
    _jobs.insert(0, job);
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (!_jobs.contains(job)) return;
      switch (kind) {
        case 'ok':
          _jobs.remove(job);
          _entries.add(ShelfEntry(
            id: 'belkin',
            title: 'Повести Белкина',
            author: 'Александр Пушкин',
            lastOpened: DateTime.now(),
            bookBytes: 410 * 1024,
          ));
        default:
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

  static String _chapterLabel(Book book, int block) {
    final i = book.chapterOf(block);
    final ch = book.chapters[i];
    if (ch.level > 1) {
      for (var j = i - 1; j >= 0; j--) {
        if (book.chapters[j].level < ch.level) return '${book.chapters[j].title} · ${ch.title}';
      }
    }
    return ch.title;
  }

  String chapterLabel(Book book, int block) => _chapterLabel(book, block);

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
    ShelfEntry e(String id, String title, String author, int hoursAgo, {bool cover = true, double? fraction, int kb = 600}) =>
        ShelfEntry(
          id: id,
          title: title,
          author: author,
          lastOpened: now.subtract(Duration(hours: hoursAgo)),
          cover: cover ? AssetImage('assets/demo/covers/$id.png') : null,
          fraction: fraction,
          bookBytes: kb * 1024,
        );
    return [
      e('kapitanskaya', 'Капитанская дочка', 'Александр Пушкин', 1, kb: 480),
      e('dama', 'Дама с собачкой. Рассказы', 'Антон Чехов', 30, kb: 520),
      e('voyna', 'Война и мир', 'Лев Толстой', 200, kb: 5800),
      e('zapiski', 'Записки охотника', 'Иван Тургенев', 260, cover: false, fraction: 0.58, kb: 1300),
      e('geroy', 'Герой нашего времени', 'Михаил Лермонтов', 400, fraction: 0.03, kb: 700),
      e('dushi', 'Мёртвые души', 'Николай Гоголь', 900, fraction: 1, kb: 1900),
    ];
  }
}
