// Converting the XML tree into linear blocks; common rules for styles and offsets.
import 'model.dart';
import 'xml.dart';

const epubNamespace = 'http://www.idpf.org/2007/ops';
Set<String> epubTypes(XmlElement e) =>
    (e.namespaced(epubNamespace, 'type') ?? '').split(RegExp(r'\s+')).toSet();
bool isEpubNote(XmlElement e) =>
    epubTypes(e).intersection({'footnote', 'endnote', 'rearnote'}).isNotEmpty;
String plain(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

// HTML 4 block content plus HTML5 sectioning/grouping and table/list parts.
// https://www.w3.org/TR/html401/sgml/dtd.html (%block;)
// https://html.spec.whatwg.org/multipage/rendering.html#the-css-user-agent-style-sheet-and-presentational-hints
const _htmlBlocks = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'center',
  'dd',
  'details',
  'dialog',
  'dir',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'html',
  'legend',
  'li',
  'main',
  'menu',
  'nav',
  'noscript',
  'ol',
  'p',
  'pre',
  'search',
  'section',
  'summary',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
  'caption',
};

class ContentBuilder {
  ContentBuilder({
    required this.fb2,
    required this.image,
    required this.noteTarget,
    this.excluded = const {},
  });
  final bool fb2;
  final String? Function(XmlElement) image;
  final String? Function(XmlElement) noteTarget;
  final Set<XmlElement> excluded;
  final List<Block> blocks = [];
  final Map<String, int> anchors = {};
  final List<(int, String, int)> boundaries = [];
  final Map<XmlElement, XmlElement> _captions = {};
  final Set<XmlElement> _captionElements = {};

  bool _empty(XmlElement e) =>
      e.local == 'br' ||
      (fb2 ? {'empty-line', 'image'} : {'hr', 'img'}).contains(e.local);

  // When recovering an unclosed empty tag, the XML parser nests the following text
  // inside it. For book content that text is its sibling, not its child.
  Iterable<Object> contentChildren(XmlElement e) sync* {
    for (final child in e.children) {
      yield child;
      if (child is XmlElement && _empty(child)) {
        yield* contentChildren(child);
      }
    }
  }

  String _titleText(XmlElement? e) {
    if (e == null || noteTarget(e) != null) return '';
    final text = contentChildren(e)
        .map((c) => c is XmlElement ? _titleText(c) : c as String)
        .join();
    return e.local == 'p' ? ' $text ' : text;
  }

  void addImage(XmlElement e) {
    final id = image(e);
    if (id == null) return;
    final caption = _captions[e];
    final line = _Inline(this, BlockKind.image);
    if (caption != null) line.visit(caption, caption: true);
    line.flush(imageId: id, force: true);
  }

  void boundary(String title, int level) {
    if (boundaries.isNotEmpty && boundaries.last.$1 == blocks.length) {
      boundaries.removeLast();
    }
    boundaries.add((blocks.length, title, level));
  }

  List<Chapter> chapters() {
    final starts = <int, (String, int)>{};
    for (final b in boundaries) {
      starts.putIfAbsent(b.$1, () => (b.$2, b.$3));
    }
    starts.putIfAbsent(0, () => ('', 1));
    final positions = starts.keys.where((i) => i < blocks.length).toList()
      ..sort();
    return [
      for (var i = 0; i < positions.length; i++)
        Chapter(
          title: starts[positions[i]]!.$1,
          level: starts[positions[i]]!.$2,
          firstBlock: positions[i],
          blockCount:
              (i + 1 < positions.length ? positions[i + 1] : blocks.length) -
              positions[i],
        ),
    ];
  }

  void anchor(XmlElement e, [int? index]) {
    final id = e.attr('id') ?? e.attr('xml:id');
    if (id != null) anchors.putIfAbsent(id, () => index ?? blocks.length);
  }

  void add(
    BlockKind kind,
    String text, [
    List<TextSpanRange> spans = const [],
    String? imageId,
  ]) => blocks.add(
    Block(
      index: blocks.length,
      kind: kind,
      text: text,
      spans: spans,
      imageId: imageId,
    ),
  );

  void render(
    XmlElement e, {
    BlockKind context = BlockKind.paragraph,
    int level = 1,
  }) {
    anchor(e);
    if (excluded.contains(e) ||
        _captionElements.contains(e) ||
        (!fb2 && epubTypes(e).contains('toc'))) {
      return;
    }
    final tag = e.local;
    if (fb2 && tag == 'section') {
      final title = plain(_titleText(e.child('title')));
      boundary(title, level);
      var resume = false;
      for (final child in contentChildren(e).whereType<XmlElement>()) {
        if (resume && child.local != 'section') boundary(title, level);
        render(
          child,
          context: context,
          level: child.local == 'section' ? level + 1 : level,
        );
        resume = child.local == 'section';
      }
      return;
    }
    if ((!fb2 && {'head', 'script', 'style'}.contains(tag)) ||
        (fb2 && tag == 'binary')) {
      return;
    }
    if ((fb2 && tag == 'empty-line') || (!fb2 && tag == 'hr')) {
      add(BlockKind.separator, '');
      return;
    }
    if ((fb2 && tag == 'image') || (!fb2 && tag == 'img')) {
      addImage(e);
      return;
    }
    if (!fb2 && tag == 'figure') {
      final caption = e.child('figcaption');
      final img = e.descendants('img').firstOrNull;
      if (img != null && caption != null) {
        _captions[img] = caption;
        _captionElements.add(caption);
      }
    }
    final heading = fb2
        ? {'title', 'subtitle'}.contains(tag)
        : RegExp(r'^h[1-6]$').hasMatch(tag);
    if (heading) {
      if (fb2 && tag == 'title' && e.elements.any((c) => c.local == 'p')) {
        for (final child in contentChildren(e).whereType<XmlElement>()) {
          render(child, context: BlockKind.heading, level: level);
        }
      } else {
        _Inline(this, BlockKind.heading).visitAndFlush(e);
      }
      return;
    }
    if ((fb2 && {'cite', 'epigraph'}.contains(tag)) ||
        (!fb2 && tag == 'blockquote')) {
      context = BlockKind.cite;
    }
    if ((fb2 && {'poem', 'stanza'}.contains(tag)) || (!fb2 && tag == 'pre')) {
      context = BlockKind.verse;
    }
    if (tag == 'tr') {
      final line = _Inline(this, BlockKind.paragraph);
      for (final c in contentChildren(e).whereType<XmlElement>()) {
        line.visit(c);
        line.write(' ');
      }
      line.flush();
      return;
    }
    if (tag == 'p' ||
        (fb2 && {'v', 'text-author', 'date'}.contains(tag)) ||
        (!fb2 && {'figcaption', 'pre'}.contains(tag))) {
      _Inline(
        this,
        tag == 'v' ? BlockKind.verse : context,
        preserveBreaks: !fb2 && tag == 'pre',
      ).visitAndFlush(e);
      return;
    }
    // Containers keep the order of mixed content. Indentation in the source XML does not create blocks.
    var line = _Inline(this, context);
    for (final child in contentChildren(e)) {
      if (child is String) {
        line.write(child);
      } else if (child is XmlElement) {
        if ((!fb2 && !_htmlBlocks.contains(child.local)) ||
            (fb2 &&
                {
                  'a',
                  'span',
                  'em',
                  'i',
                  'strong',
                  'b',
                  'sup',
                  'sub',
                  'emphasis',
                  'br',
                }.contains(child.local))) {
          line.visit(child);
          continue;
        }
        line.flush();
        render(child, context: context, level: level);
        line = _Inline(this, context);
      }
    }
    line.flush();
  }

  void removeDanglingRefs(Set<String> ids) {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      blocks[i] = Block(
        index: b.index,
        kind: b.kind,
        text: b.text,
        imageId: b.imageId,
        spans: b.spans
            .where(
              (s) => s.style != SpanStyle.noteRef || ids.contains(s.noteId),
            )
            .toList(),
      );
    }
  }
}

class _Inline {
  _Inline(this.owner, this.kind, {this.preserveBreaks = false});
  final ContentBuilder owner;
  final BlockKind kind;
  final bool preserveBreaks;
  String text = '';
  bool _afterBreak = false;
  final List<TextSpanRange> spans = [];
  final List<_OpenSpan> active = [];
  void write(String value) {
    if (_afterBreak) {
      value = value.replaceFirst(RegExp(r'^\s+'), '');
      if (value.isNotEmpty) _afterBreak = false;
    }
    final normalized = preserveBreaks
        ? value
              .replaceAll(RegExp(r'[ \t]+'), ' ')
              .replaceAll(RegExp(r' *\n *'), '\n')
        : value.replaceAll(RegExp(r'\s+'), ' ');
    text += text.endsWith(' ')
        ? normalized.replaceFirst(RegExp(r'^ +'), '')
        : normalized;
  }

  void visitAndFlush(XmlElement e) {
    visit(e);
    flush();
  }

  void visit(XmlElement e, {bool caption = false}) {
    owner.anchor(e, owner.blocks.length + (text.trim().isEmpty ? 0 : 1));
    if (owner.excluded.contains(e) ||
        (!caption && owner._captionElements.contains(e)) ||
        (!owner.fb2 && epubTypes(e).contains('toc'))) {
      return;
    }
    if (!owner.fb2 && {'head', 'script', 'style'}.contains(e.local)) return;
    if (e.local == 'br') {
      text = '${text.trimRight()}\n';
      _afterBreak = true;
      return;
    }
    if ((owner.fb2 && e.local == 'image') || (!owner.fb2 && e.local == 'img')) {
      flush();
      owner.addImage(e);
      return;
    }
    if ((owner.fb2 && e.local == 'empty-line') ||
        (!owner.fb2 && e.local == 'hr')) {
      flush();
      owner.add(BlockKind.separator, '');
      return;
    }
    // In a table row, nested paragraphs become text joined with a space, not words glued together.
    if (e.local == 'p') write(' ');
    final style = switch (e.local) {
      'emphasis' || 'em' || 'i' => SpanStyle.italic,
      'strong' || 'b' => SpanStyle.bold,
      'sup' => SpanStyle.sup,
      'sub' => SpanStyle.sub,
      _ => null,
    };
    final target = owner.noteTarget(e);
    final opened = <_OpenSpan>[
      if (style != null) _OpenSpan(text.length, style, null),
      if (target != null) _OpenSpan(text.length, SpanStyle.noteRef, target),
    ];
    active.addAll(opened);
    for (final c in owner.contentChildren(e)) {
      if (c is String) {
        write(c);
      } else {
        visit(c as XmlElement);
      }
    }
    if (e.local == 'p') write(' ');
    for (final span in opened) {
      if (text.length > span.start) spans.add(span.close(text.length));
      active.remove(span);
    }
  }

  void flush({String? imageId, bool force = false}) {
    for (final span in active) {
      if (text.length > span.start) spans.add(span.close(text.length));
      span.start = 0;
    }
    final trimmed = text.trim();
    final left = text.length - text.trimLeft().length;
    if (trimmed.isNotEmpty || force) {
      owner.add(kind, trimmed, [
        for (final s in spans)
          if ((s.end - left).clamp(0, trimmed.length) >
              (s.start - left).clamp(0, trimmed.length))
            TextSpanRange(
              start: (s.start - left).clamp(0, trimmed.length),
              end: (s.end - left).clamp(0, trimmed.length),
              style: s.style,
              noteId: s.noteId,
            ),
      ], imageId);
    }
    text = '';
    _afterBreak = false;
    spans.clear();
  }
}

class _OpenSpan {
  _OpenSpan(this.start, this.style, this.noteId);
  int start;
  final SpanStyle style;
  final String? noteId;
  TextSpanRange close(int end) =>
      TextSpanRange(start: start, end: end, style: style, noteId: noteId);
}
