import '../book/model.dart';
import '../book/speech_text.dart';
import 'fingerprint.dart';
import 'sentences.dart';
import 'voices.dart';

const segmentLength = 600;
const minimumGroupLength = 200;
const firstPartLength = 200;
const firstPartMin = 80;

final _spokenCharacters = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Half-open ranges. Each range is linear: deleted characters break the correspondence.
class SpeechMapping {
  const SpeechMapping(this.start, this.end, this.block, this.blockStart, this.blockEnd);
  final int start, end, block, blockStart, blockEnd;
}

class SpeechSegment {
  SpeechSegment(this.text, List<SpeechMapping> mappings, {this.l = segmentLength, this.lmin = minimumGroupLength})
    : mappings = List.unmodifiable(mappings);
  final String text;

  /// A line break inserted between blocks has no counterpart in the book.
  final List<SpeechMapping> mappings;
  final int l, lmin;

  SpeechSegment slice(int start, int end) => SpeechSegment(
    text.substring(start, end),
    [
      for (final m in mappings)
        if (m.end > start && m.start < end)
          SpeechMapping(
            (m.start < start ? start : m.start) - start,
            (m.end > end ? end : m.end) - start,
            m.block,
            m.blockStart + (m.start < start ? start - m.start : 0),
            m.blockEnd - (m.end > end ? m.end - end : 0),
          ),
    ],
    l: l,
    lmin: lmin,
  );
}

/// Rule 2, common to segments, the first part and the client's safety limit.
/// A minimum of 2 lets a surrogate pair be kept even if it comes first.
List<String> splitSpeech(String text, int limit) {
  if (limit < 2) {
    throw ArgumentError.value(limit, 'limit', 'At least 2 code units');
  }
  final starts = sentenceStarts(text);
  final out = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = text.length;
    if (end - start > limit) {
      end = start + limit;
      var boundary = start;
      for (final s in starts) {
        if (s > end) break;
        if (s > start) boundary = s;
      }
      if (boundary > start) {
        end = boundary;
      } else {
        for (var i = end - 1; i > start; i--) {
          if (RegExp(r'\s').hasMatch(text[i])) {
            end = i + 1;
            break;
          }
        }
      }
      if (end < text.length && _high(text.codeUnitAt(end - 1)) && _low(text.codeUnitAt(end))) {
        end--;
      }
    }
    out.add(text.substring(start, end));
    start = end;
  }
  return out;
}

bool _high(int c) => c >= 0xd800 && c <= 0xdbff;
bool _low(int c) => c >= 0xdc00 && c <= 0xdfff;

SpeechSegment _blockSegment(Block block, int l, int lmin) {
  final speech = speechText(block);
  final map = <SpeechMapping>[];
  var i = 0;
  while (i < speech.text.length) {
    final start = i++;
    while (i < speech.text.length && speech.toBlock(i) == speech.toBlock(i - 1) + 1) {
      i++;
    }
    map.add(SpeechMapping(start, i, block.index, speech.toBlock(start), speech.toBlock(i - 1) + 1));
  }
  return SpeechSegment(speech.text, map, l: l, lmin: lmin);
}

List<SpeechSegment> chapterSegments(List<Block> blocks, {int l = segmentLength, int lmin = minimumGroupLength}) {
  if (l < 2 || lmin < 0) throw ArgumentError('Requires l >= 2 and lmin >= 0');
  final out = <SpeechSegment>[];
  SpeechSegment? group;
  void flush() {
    if (group != null) out.add(group!);
    group = null;
  }

  for (final block in blocks) {
    if (!block.isSpoken) continue;
    final s = _blockSegment(block, l, lmin);
    if (!_spokenCharacters.hasMatch(s.text)) continue;
    if (block.kind == BlockKind.heading || s.text.length >= lmin || s.text.length > l) {
      flush();
      var offset = 0;
      for (final text in splitSpeech(s.text, l)) {
        out.add(s.slice(offset, offset + text.length));
        offset += text.length;
      }
    } else {
      if (group != null && group!.text.length + 1 + s.text.length > l) flush();
      if (group == null) {
        group = s;
      } else {
        final shift = group!.text.length + 1;
        group = SpeechSegment(
          '${group!.text}\n${s.text}',
          [
            ...group!.mappings,
            for (final m in s.mappings)
              SpeechMapping(m.start + shift, m.end + shift, m.block, m.blockStart, m.blockEnd),
          ],
          l: l,
          lmin: lmin,
        );
      }
    }
  }
  flush();
  return out;
}

/// The canonical split is not recomputed from the start place: only the first segment changes.
/// The offset in Block.text is brought to the sentence start by the existing algorithm.
List<SpeechSegment> segmentsFrom(
  List<Block> blocks, {
  required int block,
  int offset = 0,
  int l = segmentLength,
  int lmin = minimumGroupLength,
}) {
  final all = chapterSegments(blocks, l: l, lmin: lmin);
  final source = blocks.where((b) => b.index == block).firstOrNull;
  final speech = source == null ? null : speechText(source);
  final at = speech == null ? 0 : speech.toBlock(sentenceStartAt(speech.text, speech.fromBlock(offset)));
  for (var i = 0; i < all.length; i++) {
    final s = all[i];
    for (final m in s.mappings) {
      if (m.block > block || (m.block == block && m.blockEnd > at)) {
        final start = m.start + (m.block == block && at > m.blockStart ? at - m.blockStart : 0);
        return [s.slice(start, s.text.length), ...all.skip(i + 1)];
      }
    }
  }
  return [];
}

List<SpeechSegment> segmentParts(SpeechSegment segment) {
  if (segment.text.isEmpty) return [];
  final starts = sentenceStarts(segment.text);
  // Take the minimum whole sentences sufficient for the first part; the limit of 200 is applied by rule 2.
  final sentenceEnd = starts.skip(1).where((end) => end >= firstPartMin).firstOrNull ?? segment.text.length;
  final end = splitSpeech(segment.text.substring(0, sentenceEnd), firstPartLength).first.length;
  return [segment.slice(0, end), if (end < segment.text.length) segment.slice(end, segment.text.length)];
}

class SynthesisUnit {
  const SynthesisUnit(this.segment, this.fingerprint);
  final SpeechSegment segment;
  final String fingerprint;
  String get text => segment.text;
}

class SegmentReadiness {
  SegmentReadiness(this.ready, List<SynthesisUnit> units, List<SynthesisUnit> requests)
    : units = List.unmodifiable(units),
      requests = List.unmodifiable(requests);
  final bool ready;

  /// Playback order: a whole file or parts, including ones not ready yet.
  final List<SynthesisUnit> units;
  final List<SynthesisUnit> requests;
}

SegmentReadiness segmentReadiness(
  SpeechSegment segment,
  VoiceProfile profile,
  String audioFormat,
  bool Function(String fingerprint) exists, {
  bool startup = false,
}) {
  SynthesisUnit unit(SpeechSegment s) => SynthesisUnit(s, fingerprint(s.text, profile, audioFormat));
  final whole = unit(segment);
  if (exists(whole.fingerprint)) return SegmentReadiness(true, [whole], []);
  final parts = segmentParts(segment).map(unit).toList();
  if (parts.isEmpty) return SegmentReadiness(true, [], []);
  final present = [for (final p in parts) exists(p.fingerprint)];
  if (startup || present.any((p) => p)) {
    final missing = [
      for (var i = 0; i < parts.length; i++)
        if (!present[i]) parts[i],
    ];
    return SegmentReadiness(missing.isEmpty, parts, missing);
  }
  return SegmentReadiness(false, [whole], [whole]);
}
