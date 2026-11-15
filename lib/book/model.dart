// Модель книги (ARCHITECTURE.md, раздел 3). Чистый Dart, без Flutter.
//
// Все смещения — кодовые единицы UTF-16, то есть индексы строки Dart, по `Block.text`.

enum BlockKind { heading, paragraph, image, verse, cite, separator }

enum SpanStyle { italic, bold, sup, sub, noteRef }

class TextSpanRange {
  const TextSpanRange({
    required this.start,
    required this.end,
    required this.style,
    this.noteId,
  });

  final int start;
  final int end;
  final SpanStyle style;

  /// Только у [SpanStyle.noteRef].
  final String? noteId;

  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'style': style.name,
    if (noteId != null) 'noteId': noteId,
  };

  factory TextSpanRange.fromJson(Map<String, Object?> json) => TextSpanRange(
    start: json['start']! as int,
    end: json['end']! as int,
    style: SpanStyle.values.byName(json['style']! as String),
    noteId: json['noteId'] as String?,
  );
}

class Block {
  const Block({
    required this.index,
    required this.kind,
    required this.text,
    this.spans = const [],
    this.imageId,
  });

  final int index;
  final BlockKind kind;

  /// Строка без разметки. У картинки — подпись (может быть пустой).
  final String text;
  final List<TextSpanRange> spans;
  final String? imageId;

  Map<String, Object?> toJson() => {
    'index': index,
    'kind': kind.name,
    'text': text,
    'spans': [for (final s in spans) s.toJson()],
    if (imageId != null) 'imageId': imageId,
  };

  /// Блоки, которые читаются вслух (А§3).
  bool get isSpoken =>
      kind == BlockKind.heading ||
      kind == BlockKind.paragraph ||
      kind == BlockKind.verse ||
      kind == BlockKind.cite;

  factory Block.fromJson(Map<String, Object?> json) => Block(
    index: json['index'] as int? ?? 0,
    kind: BlockKind.values.byName(json['kind']! as String),
    text: json['text']! as String,
    spans: [
      for (final s in (json['spans'] as List<Object?>? ?? const []))
        TextSpanRange.fromJson(s! as Map<String, Object?>),
    ],
    imageId: json['imageId'] as String?,
  );
}

class Chapter {
  const Chapter({
    required this.title,
    required this.level,
    required this.firstBlock,
    required this.blockCount,
  });

  final String title;
  final int level;
  final int firstBlock;
  final int blockCount;

  Map<String, Object?> toJson() => {
    'title': title,
    'level': level,
    'firstBlock': firstBlock,
    'blockCount': blockCount,
  };

  int get endBlock => firstBlock + blockCount;

  bool contains(int block) => block >= firstBlock && block < endBlock;

  factory Chapter.fromJson(Map<String, Object?> json) => Chapter(
    title: json['title']! as String,
    level: json['level']! as int,
    firstBlock: json['firstBlock']! as int,
    blockCount: json['blockCount']! as int,
  );
}

class Note {
  const Note({required this.id, required this.blocks});

  final String id;
  final List<Block> blocks;

  Map<String, Object?> toJson() => {
    'id': id,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  factory Note.fromJson(Map<String, Object?> json) => Note(
    id: json['id']! as String,
    blocks: [
      for (final b in json['blocks']! as List<Object?>)
        Block.fromJson(b! as Map<String, Object?>),
    ],
  );
}

/// Книга без единого блока не создаётся: разбор такой файл отклоняет («Не удалось прочитать книгу», FR-B6),
/// и до экрана чтения она не доходит.
class EmptyBookException implements Exception {
  const EmptyBookException();

  @override
  String toString() => 'EmptyBookException: в книге нет ни одного блока';
}

class Book {
  /// Раздел без собственных блоков (`blockCount == 0`) в главы не попадает: линейное разбиение А§3 — каждый
  /// блок в одной главе — без него не нарушается, а страницы у такого раздела нет. Его заголовок, если он есть в
  /// файле, — блок соседней главы.
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.language,
    required List<Chapter> chapters,
    required this.blocks,
    required this.notes,
    this.parserVersion = 1,
  }) : _charsBefore = _prefix(_nonEmpty(blocks)),
       chapters = _chaptersFor(chapters, blocks.length);

  static List<Block> _nonEmpty(List<Block> blocks) {
    if (blocks.isEmpty) throw const EmptyBookException();
    return blocks;
  }

  /// Пустые разделы отбрасываются; если глав не осталось, книга — одна глава без названия (как TXT, FR-B5).
  static List<Chapter> _chaptersFor(List<Chapter> chapters, int blockCount) {
    final kept = chapters.where((c) => c.blockCount > 0).toList();
    if (kept.isEmpty) {
      kept.add(
        Chapter(title: '', level: 1, firstBlock: 0, blockCount: blockCount),
      );
    }
    return List.unmodifiable(kept);
  }

  final String id;
  final String title;
  final String author;
  final String language;
  final List<Chapter> chapters;
  final List<Block> blocks;
  final Map<String, Note> notes;
  final int parserVersion;
  final List<int> _charsBefore;

  int get totalChars => _charsBefore.last;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'language': language,
    'parserVersion': parserVersion,
    'totalChars': totalChars,
    'chapters': [for (final c in chapters) c.toJson()],
    'blocks': [for (final b in blocks) b.toJson()],
    'notes': [for (final n in notes.values) n.toJson()],
  };

  /// Число знаков до начала блока [block] (А§4, `charsBefore`).
  int charsBefore(int block) => _charsBefore[block.clamp(0, blocks.length)];

  /// Доля книги по знакам для места (блок, смещение).
  double fractionAt(int block, int offset) => totalChars == 0
      ? 0
      : ((charsBefore(block) + offset) / totalChars).clamp(0.0, 1.0);

  /// Место по доле книги: блок и смещение в нём.
  (int block, int offset) placeAt(double fraction) {
    final target = (fraction.clamp(0.0, 1.0) * totalChars).round();
    var lo = 0;
    var hi = blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_charsBefore[mid] <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final offset = (target - _charsBefore[lo]).clamp(0, blocks[lo].text.length);
    return (lo, offset);
  }

  int chapterOf(int block) {
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (chapters[i].firstBlock <= block) return i;
    }
    return 0;
  }

  static List<int> _prefix(List<Block> blocks) {
    final out = List<int>.filled(blocks.length + 1, 0);
    for (var i = 0; i < blocks.length; i++) {
      out[i + 1] = out[i] + blocks[i].text.length;
    }
    return out;
  }

  factory Book.fromJson(Map<String, Object?> json) {
    final blocks = <Block>[];
    final rawBlocks = json['blocks']! as List<Object?>;
    for (var i = 0; i < rawBlocks.length; i++) {
      final b = Block.fromJson(rawBlocks[i]! as Map<String, Object?>);
      blocks.add(
        Block(
          index: i,
          kind: b.kind,
          text: b.text,
          spans: b.spans,
          imageId: b.imageId,
        ),
      );
    }
    return Book(
      id: json['id']! as String,
      title: json['title']! as String,
      author: json['author']! as String,
      language: json['language'] as String? ?? 'ru',
      parserVersion: json['parserVersion'] as int? ?? 1,
      chapters: [
        for (final c in json['chapters']! as List<Object?>)
          Chapter.fromJson(c! as Map<String, Object?>),
      ],
      blocks: blocks,
      notes: {
        for (final n in (json['notes'] as List<Object?>? ?? const []))
          (n! as Map<String, Object?>)['id']! as String: Note.fromJson(
            n as Map<String, Object?>,
          ),
      },
    );
  }
}
