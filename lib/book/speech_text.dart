// Text for speech (ARCHITECTURE.md, section 3): the block text without structural footnote marks (`noteRef`) and
// without the stress mark U+0301, with a mapping of offsets back into `Block.text`. Pure Dart.
//
// It is used to find sentence boundaries (start of "Listen", А§5) — a footnote mark after a period does not hide the
// start of the next sentence. It is also used to build narration segments (А§6.1).

import 'model.dart';

const _stress = '́';

class SpeechText {
  const SpeechText(this.text, this._toBlock);

  /// What is pronounced.
  final String text;

  /// The offset in `Block.text` for each offset in [text] and for its end (length `text.length + 1`).
  final List<int> _toBlock;

  /// The offset in `Block.text` corresponding to the speech-text offset [i].
  int toBlock(int i) => _toBlock[i.clamp(0, _toBlock.length - 1)];

  /// The first speech-text offset that is in the block no earlier than [blockOffset].
  int fromBlock(int blockOffset) {
    for (var i = 0; i < _toBlock.length; i++) {
      if (_toBlock[i] >= blockOffset) return i;
    }
    return text.length;
  }
}

SpeechText speechText(Block block) {
  final skip = List<bool>.filled(block.text.length, false);
  for (final s in block.spans) {
    if (s.style != SpanStyle.noteRef) continue;
    for (var i = s.start; i < s.end && i < skip.length; i++) {
      skip[i] = true;
    }
  }
  final out = StringBuffer();
  final map = <int>[];
  for (var i = 0; i < block.text.length; i++) {
    if (skip[i] || block.text[i] == _stress) continue;
    out.write(block.text[i]);
    map.add(i);
  }
  map.add(block.text.length);
  return SpeechText(out.toString(), map);
}
