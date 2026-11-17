// Book model (ARCHITECTURE.md, section 3). Pure Dart, no Flutter.
//
// All offsets are UTF-16 code units, i.e. indices into the Dart string `Block.text`.

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

  /// Only for [SpanStyle.noteRef].
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

  /// Plain text without markup. For an image — the caption (may be empty).
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

  /// Blocks that are read aloud (A§3).
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

/// A book without a single block is not created: parsing rejects such a file ("Could not read the book", FR-B6),
/// and it never reaches the reading screen.
class EmptyBookException implements Exception {
  const EmptyBookException();

  @override
  String toString() => 'EmptyBookException: в книге нет ни одного блока';
}

class Book {
  /// A section without blocks of its own (`blockCount == 0`) does not become a chapter: the linear partition of A§3 —
  /// each block in exactly one chapter — is not violated without it, and such a section has no page. Its heading, if it
  /// is in the file, is a block of the neighboring chapter.
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

  /// Empty sections are dropped; if no chapters remain, the book is one chapter without a title (like TXT, FR-B5).
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

  /// Number of characters before the start of block [block] (A§4, `charsBefore`).
  int charsBefore(int block) => _charsBefore[block.clamp(0, blocks.length)];

  /// Fraction of the book by characters for a place (block, offset).
  double fractionAt(int block, int offset) => totalChars == 0
      ? 0
      : ((charsBefore(block) + offset) / totalChars).clamp(0.0, 1.0);

  /// A place from a book fraction: the block and the offset in it.
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

/// A label for display only: for an unnamed chapter — the first non-empty block of its text.
/// The book model is not changed. Take up to 12 words for a one-line label so that
/// the header does not lay out a block of hundreds of thousands of characters in full; the widget adds width clipping.
String chapterLabel(Book book, int chapter, {bool includeParent = true}) {
  final ch = book.chapters[chapter];
  if (ch.title.trim().isEmpty) {
    for (var i = ch.firstBlock; i < ch.endBlock; i++) {
      final words = RegExp(r'\S+').allMatches(book.blocks[i].text).take(13).map((m) => m.group(0)!).toList();
      if (words.isNotEmpty) {
        return words.length > 12 ? '${words.take(12).join(' ')}…' : words.join(' ');
      }
    }
    return '';
  }
  if (includeParent && ch.level > 1) {
    for (var j = chapter - 1; j >= 0; j--) {
      if (book.chapters[j].level < ch.level) {
        final parent = book.chapters[j].title;
        return parent.trim().isEmpty ? ch.title : '$parent · ${ch.title}';
      }
    }
  }
  return ch.title;
}
