// Sentence boundaries — the same rule as in splitting into segments (ARCHITECTURE.md, A§6.1, rule 2). The rule
// is general, by text form, without word lists. Pure Dart.
//
// A boundary is where, after an ending mark (. ! ? …), possibly closing quotes and brackets, comes a whitespace
// character, and:
//  (i)  the period is not after a one-letter word: «г. Москве», «А. С. Пушкин», «т. е.» — not an end;
//  (ii) the next word (after the space, and if there is a dash with a space — after the dash) starts with a capital
//       letter, a digit or an opening quote or bracket; a lowercase letter — the sentence continues:
//       «…потом заговорил», «— Стой! — крикнул он». For scripts without case, rule (ii) does not apply.
// Residual errors — abbreviations longer than one letter («см. рис. 3») — are an accepted limitation: the start a bit
// earlier or a bit later, the text is not lost.
//
// Boundaries are searched in the speech text (without footnote marks, `speechText`, A§3) and translated back into block
// offsets.

import '../book/model.dart';
import '../book/speech_text.dart';

const _enders = {'.', '!', '?', '…'};
const _closers = {'»', '"', '”', '’', ')', ']'};
const _openers = {'«', '"', '“', '„', '‘', '(', '['};
const _dashes = {'—', '–', '-'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == ' ' || c == '\r';

bool _isLetter(String c) => c.toUpperCase() != c.toLowerCase();

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

/// (ii): whether a new sentence may begin with [c]. A lowercase letter — no; a capital, a digit, an opening quote
/// or bracket — yes; a letter without case (scripts without capitals) and other marks are not checked by rule (ii).
bool _canStart(String c) {
  if (_isDigit(c) || _openers.contains(c)) return true;
  if (_isLetter(c)) return c == c.toUpperCase();
  return true;
}

/// Offsets of sentence starts in [text] (UTF-16 code units), ascending. The first is 0 if the text is not empty.
List<int> sentenceStarts(String text) {
  if (text.isEmpty) return const [];
  final out = <int>[0];
  for (var i = 1; i < text.length; i++) {
    if (_isSpace(text[i]) || !_isSpace(text[i - 1])) continue;
    // Before the spaces — the end of the previous sentence?
    var j = i - 1;
    while (j >= 0 && _isSpace(text[j])) {
      j--;
    }
    while (j >= 0 && _closers.contains(text[j])) {
      j--;
    }
    if (j < 0 || !_enders.contains(text[j])) continue;
    // (i) a period after a one-letter word — an initial or an abbreviation, not an end.
    if (text[j] == '.' && j >= 1 && _isLetter(text[j - 1]) && (j == 1 || !_isLetter(text[j - 2]))) continue;
    // (ii) the next word starts with a capital, a digit or an opening quote; after a dash with a space — the word after
    // the dash.
    var k = i;
    if (_dashes.contains(text[k]) && k + 1 < text.length && _isSpace(text[k + 1])) {
      k++;
      while (k < text.length && _isSpace(text[k])) {
        k++;
      }
      if (k >= text.length) continue;
    }
    if (!_canStart(text[k])) continue;
    out.add(i);
  }
  return out;
}

/// The start of the sentence in which the offset [offset] lies.
int sentenceStartAt(String text, int offset) {
  var best = 0;
  for (final s in sentenceStarts(text)) {
    if (s > offset) break;
    best = s;
  }
  return best;
}

/// Sentence starts of a block — by the speech text, in `Block.text` offsets.
List<int> blockSentenceStarts(Block block) {
  final speech = speechText(block);
  return [for (final s in sentenceStarts(speech.text)) speech.toBlock(s)];
}

/// The start of the sentence of the block in which the block offset [offset] lies.
int blockSentenceStartAt(Block block, int offset) {
  var best = 0;
  for (final s in blockSentenceStarts(block)) {
    if (s > offset) break;
    best = s;
  }
  return best;
}
