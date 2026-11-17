// Independent check of a sentence start for the start-position tests (FR-P3). Written anew with regular
// expressions from the text of rules A§6.1 ("end mark and a space"; (i) not after a one-letter word; (ii) next
// comes an uppercase letter, a digit or an opening quote, including after a dash and a space), rather than by
// calling `lib/tts/sentences.dart`: otherwise the test would compare the production function with itself
// (logic review 2026-11-14).

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/speech_text.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/pagination.dart';

final _end = RegExp(r'(\p{L}*)([.!?…])[»"”’)\]]*[ \t\n\r ]+$', unicode: true);
final _start = RegExp(r'^(?:[—–-][  ]+)?[\p{Lu}0-9«"“„‘(\[]', unicode: true);

/// Whether a sentence starts in the speech text [text] at offset [s].
bool looksLikeSentenceStart(String text, int s) {
  if (s == 0) return text.isNotEmpty;
  if (s >= text.length || RegExp(r'\s').hasMatch(text[s])) return false;
  final m = _end.firstMatch(text.substring(0, s));
  if (m == null) return false;
  if (m.group(2) == '.' && m.group(1)!.length == 1) return false;
  return _start.hasMatch(text.substring(s));
}

/// The first sentence start on the page [page], found by trying every offset.
ReadingPosition? firstSentenceStartOnPage(Book book, BookPageLayout page) {
  for (final f in page.fragments) {
    final block = book.blocks[f.block];
    if (f.isImage || !block.isSpoken) continue;
    final speech = speechText(block);
    for (var i = speech.fromBlock(f.start); i < speech.text.length; i++) {
      final at = speech.toBlock(i);
      if (at >= f.end) break;
      if (looksLikeSentenceStart(speech.text, i)) return ReadingPosition(f.block, at);
    }
  }
  return null;
}
