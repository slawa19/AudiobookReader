// Единственная точка входа разбора. Чистая синхронная функция, в том числе для Isolate.run.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'content.dart';
import 'model.dart';
import 'xml.dart';

const currentParserVersion = 3;

enum SourceFormat {
  fb2('fb2'),
  fb2Zip('fb2.zip'),
  epub('epub'),
  txt('txt');

  const SourceFormat(this.extension);
  final String extension;
}

enum ParseFailure { unsupported, protected, unreadable }

class BookParseException implements Exception {
  const BookParseException(this.reason, [this.technical = '']);
  final ParseFailure reason;
  final String technical;
  @override
  String toString() => 'BookParseException(${reason.name}): $technical';
}

class BookImage {
  const BookImage(this.bytes, this.mediaType);
  final Uint8List bytes;
  final String mediaType;
}

class ParsedBook {
  const ParsedBook({
    required this.book,
    required this.format,
    required this.images,
    this.cover,
  });
  final Book book;
  Map<String, Note> get notes => book.notes;
  final SourceFormat format;
  final BookImage? cover;
  final Map<String, Uint8List> images;
}

bool _zip(List<int> b) =>
    b.length >= 4 &&
    b[0] == 80 &&
    b[1] == 75 &&
    ((b[2] == 3 && b[3] == 4) ||
        (b[2] == 5 && b[3] == 6) ||
        (b[2] == 7 && b[3] == 8));
Map<String, Uint8List> _unzip(List<int> b) => {
  for (final f in ZipDecoder().decodeBytes(b, verify: true))
    if (f.isFile) f.name: f.content,
};
SourceFormat _archiveFormat(Map<String, Uint8List> files) {
  if (utf8.decode(files['mimetype'] ?? [], allowMalformed: true).trim() ==
      'application/epub+zip') {
    return SourceFormat.epub;
  }
  if (files.keys.where((n) => n.toLowerCase().endsWith('.fb2')).length == 1) {
    return SourceFormat.fb2Zip;
  }
  throw const BookParseException(ParseFailure.unsupported);
}

bool _fb2(String text) =>
    RegExp(r'^\s*<(?:[\w.-]+:)?FictionBook(?:\s|/?>)').hasMatch(
      text
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
          .replaceAll(RegExp(r'<\?[\s\S]*?\?>'), '')
          .replaceFirst(RegExp(r'<!DOCTYPE[^>]*>'), ''),
    );

/// Определяет формат по содержимому, независимо от имени файла (А§3).
SourceFormat detectFormat(List<int> bytes) {
  try {
    if (_zip(bytes)) return _archiveFormat(_unzip(bytes));
    String? xml;
    try {
      xml = decodeXml(bytes);
    } on FormatException {
      /* Двоичные данные проверяются ниже. */
    }
    if (_fb2(xml ?? latin1.decode(bytes))) return SourceFormat.fb2;
    if (bytes.length >= 4 &&
        ascii.decode(bytes.take(4).toList(), allowInvalid: true) == '%PDF') {
      throw const BookParseException(ParseFailure.unsupported);
    }
    if (bytes.take(65536).any((b) => b <= 8)) {
      throw const BookParseException(ParseFailure.unsupported);
    }
    return SourceFormat.txt;
  } on BookParseException {
    rethrow;
  } catch (e) {
    throw BookParseException(ParseFailure.unreadable, e.toString());
  }
}

ParsedBook parseBook(List<int> bytes) {
  try {
    final files = _zip(bytes) ? _unzip(bytes) : null;
    final format = files == null ? detectFormat(bytes) : _archiveFormat(files);
    final id = sha256.convert(bytes).toString().substring(0, 12);
    final result = format == SourceFormat.txt
        ? _txt(bytes, id)
        : format == SourceFormat.epub
        ? _epub(files!, id)
        : _fb(
            parseXml(
              decodeXml(
                format == SourceFormat.fb2
                    ? bytes
                    : files!.entries
                          .singleWhere(
                            (e) => e.key.toLowerCase().endsWith('.fb2'),
                          )
                          .value,
              ),
            ),
            id,
            format,
          );
    if (!result.book.blocks.any(
      (b) => b.isSpoken && b.text.trim().isNotEmpty,
    )) {
      throw const FormatException('No text blocks');
    }
    return result;
  } on BookParseException {
    rethrow;
  } catch (e) {
    throw BookParseException(ParseFailure.unreadable, e.toString());
  }
}

ParsedBook _txt(List<int> bytes, String id) {
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 239 &&
      bytes[1] == 187 &&
      bytes[2] == 191;
  final content = bom ? bytes.sublist(3) : bytes;
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = decodeWindows1251(content);
  }
  final lines = text.split(RegExp(r'\r\n|\r|\n')).map((s) => s.trim()).toList();
  // Только пустая строка МЕЖДУ строками текста включает склейку абзацев.
  final first = lines.indexWhere((s) => s.isNotEmpty);
  final last = lines.lastIndexWhere((s) => s.isNotEmpty);
  final separated = first >= 0 && lines.sublist(first, last + 1).contains('');
  final paragraphs = <String>[];
  final pending = <String>[];
  void flush() {
    if (pending.isNotEmpty) paragraphs.add(pending.join(' '));
    pending.clear();
  }

  for (final line in lines) {
    if (line.isEmpty) {
      flush();
    } else if (separated) {
      pending.add(line);
    } else {
      paragraphs.add(line);
    }
  }
  flush();
  return ParsedBook(
    book: Book(
      id: id,
      title: '',
      author: '',
      language: '',
      chapters: const [],
      blocks: [
        for (var i = 0; i < paragraphs.length; i++)
          Block(index: i, kind: BlockKind.paragraph, text: paragraphs[i]),
      ],
      notes: const {},
      parserVersion: currentParserVersion,
    ),
    format: SourceFormat.txt,
    images: const {},
  );
}

ParsedBook _fb(XmlElement root, String id, SourceFormat format) {
  if (root.local != 'FictionBook') {
    throw const FormatException('FB2: expected FictionBook root');
  }
  final info = root.child('description')?.child('title-info');
  final assets = <String, BookImage>{};
  for (final bin in root.elements.where((e) => e.local == 'binary')) {
    final key = bin.attr('id');
    if (key != null) {
      try {
        assets[key] = BookImage(
          base64.decode(bin.text.replaceAll(RegExp(r'\s'), '')),
          bin.attr('content-type') ?? 'application/octet-stream',
        );
      } on FormatException {
        // Повреждённая картинка отсутствует; основной текст остаётся доступным.
      }
    }
  }
  String? href(XmlElement e) =>
      e.namespaced('http://www.w3.org/1999/xlink', 'href') ?? e.attr('href');
  String? image(XmlElement e) {
    final key = href(e)?.replaceFirst(RegExp(r'^#'), '');
    return assets.containsKey(key) ? key : null;
  }

  final noteIds = {
    for (final body in root.elements.where(
      (e) => e.local == 'body' && e.attr('name') == 'notes',
    ))
      for (final section in body.descendants('section'))
        if (section.attr('id') != null) section.attr('id')!,
  };
  String? noteTarget(XmlElement e) {
    final target = e.local == 'a' && (href(e)?.startsWith('#') ?? false)
        ? href(e)!.substring(1)
        : null;
    return noteIds.contains(target) ? target : null;
  }

  ContentBuilder builder() =>
      ContentBuilder(fb2: true, image: image, noteTarget: noteTarget);
  final notes = <String, Note>{};
  for (final body in root.elements.where(
    (e) => e.local == 'body' && e.attr('name') == 'notes',
  )) {
    for (final section in body.descendants('section')) {
      final key = section.attr('id');
      if (key == null) continue;
      final b = builder();
      final children = b
          .contentChildren(section)
          .whereType<XmlElement>()
          .where((e) => e.local != 'section')
          .toList();
      // `title` раздела сноски — её знак («1»), а не текст: в сноску не идёт, пока у неё есть другой текст.
      final body = children.where((e) => e.local != 'title').toList();
      for (final child in body.isEmpty ? children : body) {
        b.render(child);
      }
      notes[key] = Note(id: key, blocks: b.blocks);
    }
  }
  final b = builder();
  for (final body in root.elements.where(
    (e) => e.local == 'body' && e.attr('name') != 'notes',
  )) {
    b.render(body);
  }
  _cleanRefs(b, notes);
  final coverElement = info?.child('coverpage')?.child('image');
  final coverId = coverElement == null ? null : image(coverElement);
  String author(XmlElement a) {
    final name = [
      for (final key in ['first-name', 'middle-name', 'last-name'])
        plain(a.child(key)?.text ?? ''),
    ].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : plain(a.child('nickname')?.text ?? '');
  }

  return ParsedBook(
    book: Book(
      id: id,
      title: plain(info?.child('book-title')?.text ?? ''),
      author:
          info?.elements
              .where((e) => e.local == 'author')
              .map(author)
              .join(', ') ??
          '',
      language: plain(info?.child('lang')?.text ?? ''),
      chapters: b.chapters(),
      blocks: b.blocks,
      notes: notes,
      parserVersion: currentParserVersion,
    ),
    format: format,
    cover: assets[coverId],
    images: {for (final e in assets.entries) e.key: e.value.bytes},
  );
}

void _cleanRefs(ContentBuilder b, Map<String, Note> notes) {
  b.removeDanglingRefs(notes.keys.toSet());
  for (final e in notes.entries.toList()) {
    final cleaned = ContentBuilder(
      fb2: false,
      image: (_) => null,
      noteTarget: (_) => null,
    )..blocks.addAll(e.value.blocks);
    cleaned.removeDanglingRefs(notes.keys.toSet());
    notes[e.key] = Note(id: e.key, blocks: cleaned.blocks);
  }
}

String _resolve(String document, String href) {
  final uri = Uri(path: document).resolve(href);
  if (uri.hasScheme || uri.hasAuthority || uri.path.startsWith('/')) {
    throw FormatException('EPUB: non-local reference $href');
  }
  return Uri.decodeComponent(uri.path);
}

String _fragment(String href) => Uri.decodeComponent(Uri.parse(href).fragment);
String _noteId(String document, String href) =>
    '${_resolve(document, href)}#${_fragment(href)}';
String? _tocTarget(String document, String href) {
  final uri = Uri.parse(href);
  if (uri.hasScheme || uri.hasAuthority) return null;
  return _noteId(document, href);
}

String? _epubNoteTarget(String document, String href) {
  try {
    return _noteId(document, href);
  } on FormatException {
    return null;
  }
}

ParsedBook _epub(Map<String, Uint8List> files, String id) {
  XmlElement xml(String name) {
    final bytes = files[name];
    if (bytes == null) throw FormatException('EPUB: missing $name');
    return parseXml(decodeXml(bytes));
  }

  final container = xml('META-INF/container.xml');
  final packagePath = container
      .descendants('rootfile')
      .firstOrNull
      ?.attr('full-path');
  if (packagePath == null) {
    throw const FormatException('EPUB: missing rootfile');
  }
  final package = xml(packagePath);
  final manifest = {
    for (final e in package.child('manifest')?.elements ?? <XmlElement>[])
      if (e.attr('id') != null) e.attr('id')!: e,
  };
  final spine = package.child('spine');
  if (spine == null) throw const FormatException('EPUB: missing spine');
  final documents = <String>[];
  for (final e in spine.elements.where((e) => e.local == 'itemref')) {
    final item = manifest[e.attr('idref')];
    if (item == null || item.attr('href') == null) {
      throw const FormatException('EPUB: invalid spine item');
    }
    documents.add(_resolve(packagePath, item.attr('href')!));
  }
  final encrypted = <String>{};
  if (files.containsKey('META-INF/encryption.xml')) {
    for (final ref in xml(
      'META-INF/encryption.xml',
    ).descendants('CipherReference')) {
      final uri = ref.attr('URI');
      if (uri != null) encrypted.add(_resolve('', uri));
    }
  }
  if (documents.any(encrypted.contains)) {
    throw const BookParseException(ParseFailure.protected);
  }
  final nav = manifest.values
      .where(
        (e) =>
            (e.attr('properties') ?? '').split(RegExp(r'\s+')).contains('nav'),
      )
      .firstOrNull;
  final toc = <(String, String, int)>[];
  String? navPath;
  if (nav != null) {
    navPath = _resolve(packagePath, nav.attr('href')!);
    final tree = xml(navPath);
    final tocNode = tree
        .descendants()
        .where((e) => epubTypes(e).contains('toc'))
        .firstOrNull;
    void read(XmlElement e, int depth) {
      for (final c in e.elements) {
        if (c.local == 'a' && c.attr('href') != null) {
          final target = _tocTarget(navPath!, c.attr('href')!);
          if (target != null) {
            toc.add((target, plain(c.text), depth < 1 ? 1 : depth));
          }
        } else {
          read(c, depth + (c.local == 'ol' ? 1 : 0));
        }
      }
    }

    if (tocNode != null) read(tocNode, 0);
  } else {
    final ncx =
        manifest[spine.attr('toc')] ??
        manifest.values
            .where((e) => e.attr('media-type') == 'application/x-dtbncx+xml')
            .firstOrNull;
    if (ncx != null) {
      final path = _resolve(packagePath, ncx.attr('href')!);
      void read(XmlElement e, int depth) {
        for (final point in e.elements.where((e) => e.local == 'navPoint')) {
          final href = point.child('content')?.attr('src');
          if (href != null) {
            final target = _tocTarget(path, href);
            if (target != null) {
              toc.add((
                target,
                plain(point.child('navLabel')?.text ?? ''),
                depth,
              ));
            }
          }
          read(point, depth + 1);
        }
      }

      final tree = xml(path);
      final map = tree.child('navMap');
      if (map != null) read(map, 1);
    }
  }
  final trees = <String, XmlElement>{
    for (final path in documents.toSet())
      if (path != navPath) path: xml(path),
  };
  // Документ со сносками не обязан входить в порядок чтения.
  final pending = trees.keys.toList();
  final xhtml = {
    for (final e in manifest.values)
      if (e.attr('media-type') == 'application/xhtml+xml' &&
          e.attr('href') != null)
        _resolve(packagePath, e.attr('href')!),
  };
  for (var i = 0; i < pending.length; i++) {
    final path = pending[i];
    for (final ref in trees[path]!.descendants('a')) {
      final href = ref.attr('href');
      if (href == null || _epubNoteTarget(path, href) == null) continue;
      final target = _resolve(path, href);
      if (!trees.containsKey(target) &&
          target != navPath &&
          xhtml.contains(target) &&
          files.containsKey(target) &&
          !encrypted.contains(target)) {
        trees[target] = xml(target);
        pending.add(target);
      }
    }
  }
  final noteElements = <XmlElement>{
    for (final tree in trees.values) ...tree.descendants().where(isEpubNote),
  };
  final noteIds = {
    for (final entry in trees.entries)
      for (final node in entry.value.descendants().where(isEpubNote))
        if (node.attr('id') != null) '${entry.key}#${node.attr('id')}',
  };
  final images = <String, Uint8List>{};
  ContentBuilder builder(String path, {XmlElement? note}) => ContentBuilder(
    fb2: false,
    excluded: {...noteElements}..remove(note),
    image: (e) {
      final src = e.attr('src');
      if (src == null) return null;
      final key = _resolve(path, src);
      if (encrypted.contains(key) || !files.containsKey(key)) return null;
      images[key] = files[key]!;
      return key;
    },
    noteTarget: (e) =>
        e.local == 'a' &&
            e.attr('href') != null &&
            (epubTypes(e).contains('noteref') ||
                noteIds.contains(_epubNoteTarget(path, e.attr('href')!)))
        ? _epubNoteTarget(path, e.attr('href')!)
        : null,
  );
  final notes = <String, Note>{};
  for (final entry in trees.entries) {
    for (final node in entry.value.descendants().where(isEpubNote)) {
      final key = node.attr('id');
      if (key == null) continue;
      final b = builder(entry.key, note: node)..render(node);
      notes['${entry.key}#$key'] = Note(
        id: '${entry.key}#$key',
        blocks: b.blocks,
      );
    }
  }
  final blocks = <Block>[];
  final targets = <String, int>{};
  final documentEnds = <String, int>{};
  for (final path in documents) {
    final tree = trees[path];
    if (tree == null) continue;
    final b = builder(path);
    b.render(tree.child('body') ?? tree);
    targets['$path#'] = blocks.length;
    for (final a in b.anchors.entries) {
      targets['$path#${a.key}'] = blocks.length + a.value;
    }
    for (final block in b.blocks) {
      blocks.add(
        Block(
          index: blocks.length,
          kind: block.kind,
          text: block.text,
          spans: block.spans,
          imageId: block.imageId,
        ),
      );
    }
    documentEnds[path] = blocks.length;
  }
  final b = ContentBuilder(
    fb2: false,
    image: (_) => null,
    noteTarget: (_) => null,
  )..blocks.addAll(blocks);
  for (final item in toc) {
    final path = item.$1.split('#').first;
    final start = targets[item.$1] ?? targets['$path#'];
    // Пустой документ (или якорь после его конца) не занимает чужое начало.
    if (start != null && start < documentEnds[path]!) {
      b.boundaries.add((start, item.$2, item.$3));
    }
  }
  _cleanRefs(b, notes);
  final metadata = package.child('metadata');
  final coverItem =
      manifest.values
          .where(
            (e) => (e.attr('properties') ?? '')
                .split(RegExp(r'\s+'))
                .contains('cover-image'),
          )
          .firstOrNull ??
      manifest[metadata?.elements
          .where((e) => e.local == 'meta' && e.attr('name') == 'cover')
          .firstOrNull
          ?.attr('content')];
  BookImage? cover;
  if (coverItem?.attr('href') != null) {
    final key = _resolve(packagePath, coverItem!.attr('href')!);
    if (!encrypted.contains(key) && files.containsKey(key)) {
      cover = BookImage(
        files[key]!,
        coverItem.attr('media-type') ?? 'application/octet-stream',
      );
    }
  }
  return ParsedBook(
    book: Book(
      id: id,
      title: plain(metadata?.child('title')?.text ?? ''),
      author:
          metadata?.elements
              .where((e) => e.local == 'creator')
              .map((e) => plain(e.text))
              .join(', ') ??
          '',
      language: plain(metadata?.child('language')?.text ?? ''),
      chapters: b.chapters(),
      blocks: b.blocks,
      notes: notes,
      parserVersion: currentParserVersion,
    ),
    format: SourceFormat.epub,
    images: images,
    cover: cover,
  );
}
