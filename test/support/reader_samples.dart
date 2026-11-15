import 'dart:convert';
import 'dart:typed_data';

import 'package:audiobook_reader/book/parse.dart';

import 'book_samples.dart';

/// Образцы разбора остаются исходниками тестов reader. Вместо трёх условных байтов binary кладём настоящий
/// PNG: разборщик сохраняет его байты, а reader действительно декодирует и рисует изображение.
Map<String, ParsedBook> readerSamples(Uint8List png) {
  String fb2(String name) =>
      fixture(name).replaceAll('AQID', base64.encode(png)).replaceAll('BAUG', base64.encode(png));
  final samples = <String, ParsedBook>{
    for (final name in [
      'fb2_structure.xml',
      'fb2_inline.xml',
      'fb2_metadata.xml',
      'fb2_other_body.xml',
      'fb2_plain.xml',
      'fb2_sections.xml',
      'fb2_closed.xml',
      'fb2_unclosed.xml',
      'fb2_entities.xml',
    ])
      name: checked(utf8.encode(fb2(name))),
    'fb2_encoding.xml': checked(utf8.encode(fixture('fb2_encoding.xml').replaceFirst('windows-1251', 'UTF-8'))),
    'fb2.zip': checked(zip({'book.fb2': utf8.encode(fb2('fb2_structure.xml'))})),
    for (final name in [
      'epub_boundaries.xhtml',
      'epub_structures.xhtml',
      'epub_inline_image.xhtml',
      'epub_list.xhtml',
      'epub_mixed_figure.xhtml',
      'epub_plain_caption.xhtml',
      'epub_pre.xhtml',
      'epub_second.xhtml',
      'epub_missing_note_resource.xhtml',
      'epub_note_documents.xhtml',
      'epub_unclosed.xhtml',
      'epub_encoding.xhtml',
    ])
      name: checked(epub(content: fixture(name), raw: {'OPS/pic.png': png})),
    'epub2': checked(epub(ncx: true, cover3: false, raw: {'OPS/pic.png': png})),
    for (final type in ['footnote', 'endnote', 'rearnote'])
      for (final tag in ['aside', 'div'])
        '$type-$tag': checked(
          epub(
            content: fixture('epub_note_type.xhtml').replaceAll('TAG', tag).replaceAll('TYPE', type),
            raw: {'OPS/pic.png': png},
          ),
        ),
  };
  return samples;
}
