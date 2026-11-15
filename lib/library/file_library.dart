import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

import '../book/model.dart';
import '../book/parse.dart';
import 'library.dart';
import 'settings.dart';

typedef LibraryParser = Future<ParsedBook> Function(String path);
typedef LibraryTimer = Timer Function(Duration delay, void Function() callback);

// 256 МиБ оставляют запас для иллюстрированного EPUB, но отсекают гигабайтные архивы
// до чтения в память. Исходник и разбор живут только в рабочем изоляте.
const maxBookFileBytes = 256 * 1024 * 1024;

Future<void> _checkSize(File file) async {
  if (await file.length() > maxBookFileBytes) {
    throw const BookParseException(ParseFailure.unsupported);
  }
}

Future<ParsedBook> _parse(String path) => Isolate.run(() async {
  final file = File(path);
  await _checkSize(file);
  return parseBook(await file.readAsBytes());
});
Future<String> _bookId(String path) => Isolate.run(() async {
  final file = File(path);
  await _checkSize(file);
  return (await sha256.bind(file.openRead()).first).toString().substring(0, 12);
});

Future<Book> _readBook(String path) => Isolate.run(
  () async => Book.fromJson(
    jsonDecode(await File(path).readAsString()) as Map<String, Object?>,
  ),
);

Future<void> _writeBook(String path, Book book) => Isolate.run(() async {
  final temp = File('$path.new');
  await temp.writeAsString(jsonEncode(book.toJson()), flush: true);
  await temp.rename(path);
});

// У TXT нет метаданных: имя приходит от провайдера, а не от временной копии.
ParsedBook _txtTitle(ParsedBook parsed, String title) {
  if (parsed.format != SourceFormat.txt) return parsed;
  final book = parsed.book;
  return ParsedBook(
    book: Book(
      id: book.id,
      title: title,
      author: book.author,
      language: book.language,
      chapters: book.chapters,
      blocks: book.blocks,
      notes: book.notes,
      parserVersion: book.parserVersion,
    ),
    format: parsed.format,
    images: parsed.images,
    cover: parsed.cover,
  );
}

/// Файловая полка этапа 1. После конструктора нужно дождаться [ready].
/// Перед записью позиций книга должна быть открыта через [loadBook].
/// [parser], [clock] и [timer] подставляются в тестах; обычный разбор идёт в Isolate.run.
class FileLibrary extends Library {
  FileLibrary(
    this.root, {
    required this.settings,
    DateTime Function()? clock,
    LibraryTimer? timer,
    LibraryParser? parser,
  }) : _clock = clock ?? DateTime.now,
       _timer = timer ?? Timer.new,
       _parser = parser ?? _parse {
    ready = _start();
  }

  final Directory root;
  final AppSettings settings;
  final DateTime Function() _clock;
  final LibraryTimer _timer;
  final LibraryParser _parser;
  late final Future<void> ready;
  final Map<String, _StoredBook> _stored = {};
  final Map<String, Book> _books = {};
  final Map<String, Future<Book>> _loads = {};
  final Map<String, Future<ShelfEntry?>> _adding = {};
  final List<AddJob> _jobs = [];
  Map<DateTime, Map<String, UsageTokens>> _usage = {};
  final Set<String> _dirty = {};
  Future<void> _writer = Future.value();
  Object? _writeError;
  StackTrace? _writeStack;
  Timer? _pending;
  DateTime? _lastWrite;
  bool _settingsDirty = false;
  bool _closed = false;

  Directory _dir(String id) => Directory('${root.path}/books/$id');

  Future<void> _start() async {
    await root.create(recursive: true);
    final tmp = Directory('${root.path}/tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create();
    final books = await Directory('${root.path}/books').create();
    final config = File('${root.path}/settings.json');
    if (await config.exists()) {
      try {
        settings.restore(await _json(config));
      } on FormatException {
        // Пустой или оборванный JSON не лишает пользователя полки.
      } on TypeError {
        // Корень JSON должен быть объектом настроек.
      }
    }
    await settings.loadApiKey();
    try {
      final json = await _json(File('${root.path}/usage.json'));
      final loaded = <DateTime, Map<String, UsageTokens>>{};
      for (final entry in json.entries) {
        final month = DateTime.parse('${entry.key}-01');
        if (entry.key != _monthKey(month)) {
          throw const FormatException('Неверный месяц расхода');
        }
        loaded[month] = {
          for (final model in (entry.value! as Map<String, Object?>).entries)
            model.key: UsageTokens.fromJson(
              model.value! as Map<String, Object?>,
            ),
        };
      }
      _usage = loaded;
    } on FormatException {
      // Оборванный или неверный файл расхода не лишает пользователя полки.
    } on TypeError {
      // Схема расхода повреждена — начинаем с нуля.
    } on FileSystemException {
      // Отсутствующий или нечитаемый файл равнозначен пустому расходу.
    }
    await for (final dir in books.list()) {
      if (dir is! Directory) continue;
      try {
        final meta = await _json(File('${dir.path}/meta.json'));
        final state = await _json(File('${dir.path}/state.json'));
        final id = meta['id']! as String;
        _stored[id] = _StoredBook(meta, state, await _bytes(dir), dir);
      } catch (_) {
        // Повреждённую запись пропускаем целиком, исходник оставляем для восстановления.
      }
    }
    if (!_closed) {
      settings.addListener(_settingsChanged);
      notifyListeners();
    }
  }

  void _settingsChanged() {
    _settingsDirty = true;
    _requestWrite();
  }

  @override
  Map<DateTime, Map<String, UsageTokens>> get usage => Map.unmodifiable({
    for (final month in _usage.entries)
      month.key: Map<String, UsageTokens>.unmodifiable(month.value),
  });

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

  @override
  Future<void> recordUsage({
    required String modelId,
    required int audioTokens,
    required int inputTokens,
    DateTime? at,
  }) async {
    // Момент фиксируется до ожидания запуска и писателя, а не по времени записи.
    final local = (at ?? _clock()).toLocal();
    final month = DateTime(local.year, local.month);
    if (audioTokens < 0 || inputTokens < 0) {
      throw ArgumentError('Число токенов не может быть отрицательным');
    }
    await ready;
    if (_closed) throw StateError('Библиотека закрыта');
    await _enqueue(() async {
      final previous = _usage[month]?[modelId];
      final next = {
        ..._usage,
        month: {
          ...?_usage[month],
          modelId: UsageTokens(
            audioTokens: (previous?.audioTokens ?? 0) + audioTokens,
            inputTokens: (previous?.inputTokens ?? 0) + inputTokens,
          ),
        },
      };
      await _atomic(File('${root.path}/usage.json'), {
        for (final entry in next.entries)
          _monthKey(entry.key): {
            for (final model in entry.value.entries)
              model.key: model.value.toJson(),
          },
      });
      // Неудавшаяся запись не меняет счётчики в памяти; повтор не удвоит расход.
      _usage = next;
      if (!_closed) notifyListeners();
    });
  }

  @override
  List<ShelfEntry> get shelf {
    final entries = _stored.values.map((s) => s.entry).toList();
    final opened = entries.where((e) => e.opened).toList()
      ..sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
    final fresh = entries.where((e) => !e.opened).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return [...opened, ...fresh];
  }

  @override
  List<AddJob> get addJobs => List.unmodifiable(_jobs);

  /// Отказ до разбора: например, Android не смог скопировать выбранный файл.
  @override
  void recordFileFailure(String fileName, Object error) {
    _jobs.insert(0, AddJob(
      fileName: fileName,
      status: AddJobStatus.failed,
      failure: AddFailure.unreadable,
      technical: error.toString(),
    ));
    notifyListeners();
  }

  @override
  ShelfEntry entry(String bookId) => _stored[bookId]!.entry;

  @override
  Future<ShelfEntry?> addFile(String path, String fileName) async {
    await ready;
    if (_closed) throw StateError('Библиотека закрыта');
    final String id;
    try {
      id = await _bookId(path);
    } on BookParseException catch (error) {
      _jobs.insert(0, AddJob(
        fileName: fileName,
        status: AddJobStatus.failed,
        failure: AddFailure.values.byName(error.reason.name),
        technical: error.technical,
      ));
      notifyListeners();
      return null;
    }
    if (_stored.containsKey(id)) return entry(id);
    return _adding[id] ??= _add(path, fileName, id).whenComplete(() {
      _adding.remove(id);
    });
  }

  Future<ShelfEntry?> _add(String path, String fileName, String id) async {
    final job = AddJob(fileName: fileName, status: AddJobStatus.adding);
    _jobs.insert(0, job);
    notifyListeners();
    Directory? work;
    try {
      work = await Directory('${root.path}/tmp').createTemp('add-');
      final source = await File(path).copy('${work.path}/source');
      final parsed = _txtTitle(
        await _parser(source.path),
        fileName.replaceFirst(RegExp(r'\.[^.]*$'), ''),
      );
      if (_closed) return null;
      await source.rename('${work.path}/original.${parsed.format.extension}');
      await _writeBook('${work.path}/book.json', parsed.book);
      final meta = await _assets(work, parsed);
      final state = <String, Object?>{
        'position': null,
        'listeningPosition': null,
        'finished': false,
        'parserVersion': parsed.book.parserVersion,
        'voice': null,
        'addedAt': _timestamp('addedAt'),
        'lastOpened': null,
      };
      await _atomic(File('${work.path}/meta.json'), meta);
      await _atomic(File('${work.path}/state.json'), state);
      if (_closed) return null;
      final committed = await work.rename(_dir(id).path);
      work = null;
      _stored[id] = _StoredBook(
        meta,
        state,
        await _bytes(committed),
        committed,
      );
      _jobs.remove(job);
      if (!_closed) notifyListeners();
      return entry(id);
    } on BookParseException catch (e) {
      job.status = AddJobStatus.failed;
      job.failure = AddFailure.values.byName(e.reason.name);
      job.technical = e.technical;
      if (!_closed) notifyListeners();
      return null;
    } catch (e) {
      job.status = AddJobStatus.failed;
      job.failure = AddFailure.unreadable;
      job.technical = e.toString();
      if (!_closed) notifyListeners();
      return null;
    } finally {
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  Future<Map<String, Object?>> _assets(Directory dir, ParsedBook parsed) async {
    final sizes = <String, Object?>{};
    await Directory('${dir.path}/images').create(recursive: true);
    for (final e in parsed.images.entries) {
      await File('${dir.path}/images/${Uri.encodeComponent(e.key)}')
          .writeAsBytes(e.value);
      // Битая картинка не делает текст книги нечитаемым. У неё нет размера для раскладки.
      try {
        final codec = await ui.instantiateImageCodec(e.value);
        try {
          final frame = await codec.getNextFrame();
          sizes[e.key] = [frame.image.width, frame.image.height];
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (_) {
        /* Изображение пропускается. */
      }
    }
    if (parsed.cover != null) {
      await File('${dir.path}/cover.jpg').writeAsBytes(parsed.cover!.bytes);
    }
    return {
      'id': parsed.book.id,
      'title': parsed.book.title,
      'author': parsed.book.author,
      'totalChars': parsed.book.totalChars,
      'parserVersion': parsed.book.parserVersion,
      'cover': parsed.cover != null,
      'chapters': [for (final c in parsed.book.chapters) c.toJson()],
      'imageSizes': sizes,
    };
  }

  @override
  Future<Book> loadBook(String bookId) async {
    await ready;
    if (_books.containsKey(bookId)) return _books[bookId]!;
    return _loads[bookId] ??= _load(bookId).whenComplete(() {
      _loads.remove(bookId);
    });
  }

  Future<Book> _load(String id) async {
    final path = '${_dir(id).path}/book.json';
    var book = await _readBook(path);
    final stored = _stored[id]!;
    // Версии в meta/state дают закончить переразбор, прерванный после замены book.json.
    if (book.parserVersion < currentParserVersion ||
        stored.meta['parserVersion'] != book.parserVersion ||
        stored.state['parserVersion'] != book.parserVersion) {
      final original = await _dir(id)
          .list()
          .where(
            (f) => f is File && f.uri.pathSegments.last.startsWith('original.'),
          )
          .first;
      final parsed = _txtTitle(
        await _parser(original.path),
        stored.meta['title']! as String,
      );
      book = parsed.book;
      final next = book;
      await _enqueue(() async {
        for (final field in ['position', 'listeningPosition']) {
          final pos = stored.position(field);
          if (pos != null) stored.state[field] = _restore(next, pos).toJson();
        }
        await _writeBook(path, next);
        stored.meta = await _assets(_dir(id), parsed);
        await _atomic(File('${_dir(id).path}/meta.json'), stored.meta);
        stored.state['parserVersion'] = next.parserVersion;
        await _atomic(File('${_dir(id).path}/state.json'), stored.state);
        stored.refresh(_dir(id));
      });
    }
    _books[id] = book;
    return book;
  }

  static ReadingPosition _at(Book book, ReadingPosition pos) {
    final block = pos.block.clamp(0, book.blocks.length - 1);
    final text = book.blocks[block].text;
    return ReadingPosition(
      block,
      pos.offset.clamp(0, text.length),
      charsBefore: book.charsBefore(block),
      anchorText: text.substring(0, text.length.clamp(0, 64)),
    );
  }

  static ReadingPosition _restore(Book book, ReadingPosition pos) {
    int? found;
    for (var i = 0; i < book.blocks.length; i++) {
      if (pos.anchorText.isNotEmpty &&
          book.blocks[i].text.startsWith(pos.anchorText) &&
          (found == null ||
              (book.charsBefore(i) - pos.charsBefore).abs() <
                  (book.charsBefore(found) - pos.charsBefore).abs())) {
        found = i;
      }
    }
    if (found != null) return _at(book, ReadingPosition(found, pos.offset));
    final (block, _) = book.placeAt(
      book.totalChars == 0 ? 0 : pos.charsBefore / book.totalChars,
    );
    return _at(book, ReadingPosition(block, pos.offset));
  }

  @override
  Map<String, Size> imageSizes(String bookId) => {
    for (final e
        in (_stored[bookId]!.meta['imageSizes']! as Map<String, Object?>)
            .entries)
      e.key: Size(
        ((e.value! as List)[0] as num).toDouble(),
        ((e.value! as List)[1] as num).toDouble(),
      ),
  };
  @override
  ImageProvider image(String bookId, String imageId) => FileImage(
    File('${_dir(bookId).path}/images/${Uri.encodeComponent(imageId)}'),
  );
  @override
  ReadingPosition? positionOf(String bookId) =>
      _stored[bookId]!.position('position');
  @override
  ReadingPosition? listeningPositionOf(String bookId) =>
      _stored[bookId]!.position('listeningPosition');
  @override
  bool isFinished(String bookId) => _stored[bookId]!.state['finished']! as bool;
  @override
  String? bookVoice(String bookId) =>
      _stored[bookId]!.state['voice'] as String?;

  @override
  void savePosition(
    String bookId,
    ReadingPosition position, {
    double? fraction,
    String? chapterTitle,
  }) => _change(bookId, 'position', _at(_books[bookId]!, position).toJson());
  @override
  void saveListeningPosition(String bookId, ReadingPosition position) =>
      _change(
        bookId,
        'listeningPosition',
        _at(_books[bookId]!, position).toJson(),
      );
  @override
  void setFinished(String bookId, bool finished) =>
      _change(bookId, 'finished', finished);
  @override
  void setBookVoice(String bookId, String? voice) =>
      _change(bookId, 'voice', voice);
  @override
  void markOpened(String bookId) =>
      _change(bookId, 'lastOpened', _timestamp('lastOpened'));

  String _timestamp(String field) {
    var now = _clock();
    for (final book in _stored.values) {
      final raw = book.state[field] as String?;
      if (raw == null) continue;
      final last = DateTime.parse(raw);
      if (!now.isAfter(last)) now = last.add(const Duration(microseconds: 1));
    }
    return now.toIso8601String();
  }

  void _change(String id, String field, Object? value) {
    if (_closed) throw StateError('Библиотека закрыта');
    final stored = _stored[id]!;
    stored.state[field] = value;
    stored.refresh(_dir(id));
    _dirty.add(id);
    _requestWrite();
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writer.then((_) => operation());
    _writer = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _requestWrite({bool immediate = false}) {
    final elapsed = _lastWrite == null
        ? const Duration(seconds: 1)
        : _clock().difference(_lastWrite!);
    if (immediate || elapsed >= const Duration(seconds: 1)) {
      _pending?.cancel();
      _pending = null;
      // Ошибки фоновой записи сохраняет писатель; flush отдаёт их вызывающему коду.
      unawaited(_enqueue(() async {
        try {
          await _writeDirty();
        } catch (error, stack) {
          _writeError ??= error;
          _writeStack ??= stack;
        }
      }));
    } else {
      _pending ??= _timer(const Duration(seconds: 1) - elapsed, () {
        _pending = null;
        _requestWrite(immediate: true);
      });
    }
  }

  Future<void> _writeDirty({bool force = false}) async {
    if (_dirty.isEmpty && !_settingsDirty) return;
    // Проверяем время у самого диска: очередь могла задержаться за переразбором.
    final elapsed = _lastWrite == null
        ? const Duration(seconds: 1)
        : _clock().difference(_lastWrite!);
    if (!force && elapsed < const Duration(seconds: 1)) {
      _pending ??= _timer(const Duration(seconds: 1) - elapsed, () {
        _pending = null;
        _requestWrite();
      });
      return;
    }
    _lastWrite = _clock();
    final ids = _dirty.toList();
    for (final id in ids) {
      final state = _stored[id]?.state;
      // Пока идёт запись, новое изменение может снова пометить книгу грязной.
      _dirty.remove(id);
      if (state != null) {
        try {
          await _atomic(File('${_dir(id).path}/state.json'), state);
        } catch (_) {
          _dirty.add(id);
          rethrow;
        }
      }
    }
    if (_settingsDirty) {
      _settingsDirty = false;
      try {
        await _atomic(File('${root.path}/settings.json'), settings.toJson());
      } catch (_) {
        _settingsDirty = true;
        rethrow;
      }
    }
  }

  @override
  Future<void> flush() async {
    await ready;
    _pending?.cancel();
    _pending = null;
    // Сбой хранилища ключа не мешает дописать позицию и обычные настройки.
    await Future.wait([
      settings.flushApiKey(),
      _enqueue(() async {
        final error = _writeError;
        final stack = _writeStack;
        _writeError = null;
        _writeStack = null;
        if (error != null) Error.throwWithStackTrace(error, stack!);
        await _writeDirty(force: true);
      }),
    ]);
  }

  @override
  Future<void> deleteBook(String bookId) async {
    await ready;
    final loading = _loads[bookId];
    if (loading != null) await loading;
    await _enqueue(() async {
      final tomb = await Directory('${root.path}/tmp').createTemp('delete-');
      await _dir(bookId).rename('${tomb.path}/book');
      _stored.remove(bookId);
      _books.remove(bookId);
      _dirty.remove(bookId);
      notifyListeners();
      await tomb.delete(recursive: true);
    });
  }

  @override
  void dismissAddJob(AddJob job) {
    if (job.status != AddJobStatus.failed) return;
    _jobs.remove(job);
    notifyListeners();
  }

  /// Сначала await flush(), затем dispose(). Сам dispose не обещает асинхронную запись.
  @override
  void dispose() {
    _closed = true;
    _pending?.cancel();
    settings.removeListener(_settingsChanged);
    super.dispose();
  }
}

Future<Map<String, Object?>> _json(File file) async =>
    jsonDecode(await file.readAsString()) as Map<String, Object?>;

Future<void> _atomic(File file, Map<String, Object?> value) async {
  // Снимок снимается до первого await; следующая команда меняет уже актуальную память.
  final text = jsonEncode(value);
  final next = File('${file.path}.new');
  await next.writeAsString(text, flush: true);
  await next.rename(file.path);
}

Future<int> _bytes(Directory dir) async {
  var bytes = 0;
  await for (final file in dir.list(recursive: true, followLinks: false)) {
    if (file is File) bytes += await file.length();
  }
  return bytes;
}

class _StoredBook {
  _StoredBook(this.meta, this.state, this.bytes, Directory dir) {
    refresh(dir);
  }
  Map<String, Object?> meta;
  final Map<String, Object?> state;
  final int bytes;
  late ShelfEntry entry;

  ReadingPosition? position(String field) => state[field] == null
      ? null
      : ReadingPosition.fromJson(state[field]! as Map<String, Object?>);

  void refresh(Directory dir) {
    final pos = position('position');
    final total = meta['totalChars']! as int;
    final chapters = (meta['chapters']! as List)
        .map((c) => Chapter.fromJson(c as Map<String, Object?>))
        .toList();
    final chapter = chapters.lastWhere(
      (c) => c.firstBlock <= (pos?.block ?? 0),
    );
    var label = chapter.title;
    final index = chapters.indexOf(chapter);
    for (var i = index - 1; i >= 0; i--) {
      if (chapters[i].level < chapter.level) {
        label = '${chapters[i].title} · $label';
        break;
      }
    }
    final opened = state['lastOpened'] as String?;
    entry = ShelfEntry(
      id: meta['id']! as String,
      title: meta['title']! as String,
      author: meta['author']! as String,
      addedAt: DateTime.parse(state['addedAt']! as String),
      lastOpened: opened == null ? null : DateTime.parse(opened),
      cover: meta['cover'] == true
          ? FileImage(File('${dir.path}/cover.jpg'))
          : null,
      fraction: state['finished'] == true
          ? 1
          : opened == null
          ? null
          : total == 0
          ? 0
          : (((pos?.charsBefore ?? 0) + (pos?.offset ?? 0)) / total).clamp(
              0.0,
              // Конец позиции сам по себе не означает «дочитана» (FR-L4).
              (total - 1) / total,
            ),
      chapterTitle: label,
      bookBytes: bytes,
    );
  }
}
