import 'dart:math';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/speech_text.dart';
import 'package:audiobook_reader/tts/fingerprint.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

const p = VoiceProfile(model: 'gemini-3.8-flash-tts', voiceId: 'Aoede', style: 'Стиль');
Block b(int index, String text, {BlockKind kind = BlockKind.paragraph, List<TextSpanRange> spans = const []}) =>
    Block(index: index, kind: kind, text: text, spans: spans);
List<String> texts(List<SpeechSegment> segments) => segments.map((s) => s.text).toList();
List<List<int>> maps(SpeechSegment s) => [
  for (final m in s.mappings) [m.start, m.end, m.block, m.blockStart, m.blockEnd],
];

void main() {
  test('без букв и цифр: нет отрезка, группа не прерывается; Unicode речь сохраняется', () {
    for (final text in ['', ' ', '* * *', '…', '— § 😀 \u0301']) {
      for (final kind in [BlockKind.paragraph, BlockKind.heading, BlockKind.verse, BlockKind.cite]) {
        expect(chapterSegments([b(0, text, kind: kind)]), isEmpty);
        final grouped = chapterSegments([b(0, 'До'), b(1, text, kind: kind), b(2, 'После')]);
        expect(texts(grouped), ['До\nПосле']);
        expect(maps(grouped.single), [[0, 2, 0, 0, 2], [3, 8, 2, 0, 5]]);
      }
    }
    final notes = b(1, '1 2', spans: [
      const TextSpanRange(start: 0, end: 1, style: SpanStyle.noteRef),
      const TextSpanRange(start: 2, end: 3, style: SpanStyle.noteRef),
    ]);
    expect(chapterSegments([notes]), isEmpty);
    expect(texts(chapterSegments([b(0, 'До'), notes, b(2, 'После')])), ['До\nПосле']);
    for (final text in ['1.', '— Да.', '§ 5', 'А', '中', 'ع', '४', '٢', 'Ⅳ', '𐐀', '𝟙']) {
      expect(texts(chapterSegments([b(0, text)])), [text]);
    }
    expect(texts(chapterSegments([b(0, 'До'), b(1, 'А', kind: BlockKind.heading), b(2, 'После')])),
        ['До', 'А', 'После']);
  });

  test('первая часть: минимум 80 целыми предложениями, максимум 200, без потери соответствий', () {
    for (final opening in ['— Да. ', '1. ']) {
      final second = '${'Б' * (80 - opening.length - 2)}. ';
      final first = '$opening$second';
      expect(first.length, 80);
      final text = '$firstТретье предложение.';
      final segment = chapterSegments([b(7, text)]).single;
      final parts = segmentParts(segment);
      expect(texts(parts), [first, 'Третье предложение.']);
      expect(maps(parts.first), [[0, 80, 7, 0, 80]]);
      expect(maps(parts.last), [[0, 19, 7, 80, 99]]);
    }
    final first = '${'Б' * 118}. ';
    expect(texts(segmentParts(SpeechSegment('$firstДалее.', []))), [first, 'Далее.']);
    for (final n in [79, 80]) {
      final text = 'Да. ${'Б' * (n - 5)}.';
      expect(text.length, n);
      expect(texts(segmentParts(SpeechSegment(text, []))), [text]);
    }
    final sentences = 'Да. ' * 25;
    expect(texts(segmentParts(SpeechSegment(sentences, []))), ['Да. ' * 20, 'Да. ' * 5]);
    final long = '${'Б' * 120} ${'В' * 100}. Далее.';
    expect(segmentParts(SpeechSegment(long, [])).first.text, '${'Б' * 120} ');
  });

  test('правило 1: заголовок отдельно; соседние обычные короткие блоки объединяются', () {
    expect(texts(chapterSegments([b(0, 'До'), b(1, 'Глава', kind: BlockKind.heading), b(2, 'После')])), [
      'До',
      'Глава',
      'После',
    ]);
    expect(texts(chapterSegments([b(0, 'До'), b(1, 'Текст'), b(2, 'После')])), ['До\nТекст\nПосле']);
  });

  test('правила 2 и 4: ровно L — один; длиннее L — предложения, пробел, жёсткая граница', () {
    expect(texts(chapterSegments([b(0, 'я' * 10)], l: 10, lmin: 4)), ['я' * 10]);
    expect(texts(chapterSegments([b(0, 'Раз. Два. Три.')], l: 10, lmin: 4)), ['Раз. Два. ', 'Три.']);
    expect(texts(chapterSegments([b(0, 'Длинные слова здесь')], l: 10)), ['Длинные ', 'слова ', 'здесь']);
    expect(texts(chapterSegments([b(0, 'я' * 23)], l: 10)), ['я' * 10, 'я' * 10, 'яяя']);
    expect(texts(chapterSegments([b(0, 'я' * 11, kind: BlockKind.heading)], l: 10)), ['я' * 10, 'я']);
  });

  test('правило 3: строго меньше Lmin; newline входит в L; пропущенное группу не прерывает', () {
    expect(texts(chapterSegments([b(0, 'ааа'), b(1, 'ббб')], l: 7, lmin: 4)), ['ааа\nббб']);
    expect(texts(chapterSegments([b(0, 'ааа'), b(1, 'ббб')], l: 6, lmin: 4)), ['ааа', 'ббб']);
    expect(texts(chapterSegments([b(0, 'ааа'), b(1, 'бббб'), b(2, 'в')], l: 20, lmin: 4)), ['ааа', 'бббб', 'в']);
    expect(
      texts(
        chapterSegments([
          b(0, 'До'),
          b(1, 'Подпись', kind: BlockKind.image),
          b(2, '***', kind: BlockKind.separator),
          b(3, ''),
          b(4, '1', spans: [const TextSpanRange(start: 0, end: 1, style: SpanStyle.noteRef)]),
          b(5, 'После'),
        ]),
      ),
      ['До\nПосле'],
    );
    expect(chapterSegments([b(0, 'Подпись', kind: BlockKind.image)]), isEmpty);
  });

  test('все длины по речи; соответствия точные через сноски и ударения, newline не привязан', () {
    final blocks = [
      b(10, 'А\u0301б1вг', spans: [const TextSpanRange(start: 3, end: 4, style: SpanStyle.noteRef)]),
      b(11, 'Конец'),
    ];
    final s = chapterSegments(blocks).single;
    expect(s.text, 'Абвг\nКонец');
    expect(maps(s), [
      [0, 1, 10, 0, 1],
      [1, 2, 10, 2, 3],
      [2, 4, 10, 4, 6],
      [5, 10, 11, 0, 5],
    ]);
    final cut = s.slice(1, 7);
    expect(cut.text, 'бвг\nКо');
    expect(maps(cut), [
      [0, 1, 10, 2, 3],
      [1, 3, 10, 4, 6],
      [4, 6, 11, 0, 2],
    ]);
    expect(texts(chapterSegments([blocks.first, b(11, 'Да')], l: 7, lmin: 5)), ['Абвг\nДа']);
  });

  test('границы предложений берутся из sentences: обе стороны (i) и (ii), сноска после точки', () {
    // При таком L ошибочная граница после «г.» изменила бы первый кусок: проверка не вакуумна.
    expect(splitSpeech('г. Москве сегодня. Потом.', 12).first, 'г. Москве ');
    expect(splitSpeech('Он. Москве сегодня. Потом.', 12).first, 'Он. ');
    expect(splitSpeech('Стой! — крикнул он. Потом.', 10), ['Стой! — ', 'крикнул ', 'он. Потом.']);
    expect(splitSpeech('Стой! — Крикнул он. Потом.', 10), ['Стой! ', '— Крикнул ', 'он. Потом.']);
    final s = chapterSegments([
      b(0, 'Раз.1 Потом.', spans: [const TextSpanRange(start: 4, end: 5, style: SpanStyle.noteRef)]),
    ], l: 7).first;
    expect(s.text, 'Раз. ');
    expect(maps(s), [
      [0, 4, 0, 0, 4],
      [4, 5, 0, 5, 6],
    ]);
  });

  test('части: короткий отрезок целиком, максимум 200; остаток один; пустого остатка нет', () {
    SpeechSegment s(String t) => SpeechSegment(t, []);
    expect(texts(segmentParts(s('Первое. Второе. Третье.'))), ['Первое. Второе. Третье.']);
    expect(texts(segmentParts(s('Первое.'))), ['Первое.']);
    expect(texts(segmentParts(s('я' * 201))), ['я' * 200, 'я']);
    expect(texts(segmentParts(s('я' * 200))), ['я' * 200]);
    expect(segmentParts(s('')), isEmpty);
  });

  test('готовность: целый приоритетен; обе части готовы; одна готова — только недостающая (SC-2.1)', () {
    final s = chapterSegments([b(0, '${'Б' * 118}. Второе.')]).single;
    String fp(SpeechSegment s) => fingerprint(s.text, p, 'aac');
    final parts = segmentParts(s);
    final cases = <(Set<String>, bool, List<String>)>[
      ({fp(s)}, true, []),
      ({...parts.map(fp)}, true, []),
      ({fp(parts[0])}, false, [parts[1].text]),
      ({fp(parts[1])}, false, [parts[0].text]),
      ({}, false, [s.text]),
    ];
    for (final (files, ready, requests) in cases) {
      final r = segmentReadiness(s, p, 'aac', files.contains);
      expect(r.ready, ready);
      expect(r.requests.map((u) => u.text), requests);
    }
    final startup = segmentReadiness(s, p, 'aac', (_) => false, startup: true);
    expect(startup.ready, isFalse);
    expect(startup.requests.map((u) => u.text), texts(parts));
    expect(startup.units.map((u) => u.text), texts(parts));
    expect(segmentReadiness(s, p, 'aac', {fp(s)}.contains, startup: true).requests, isEmpty);
    expect(segmentReadiness(s, p, 'opus', {fp(s), ...parts.map(fp)}.contains).ready, isFalse);
    const other = VoiceProfile(model: 'gemini-3.8-flash-tts', voiceId: 'Aoede', style: 'Другой');
    expect(segmentReadiness(s, other, 'aac', {fp(s), ...parts.map(fp)}.contains).ready, isFalse);
  });

  test('готовность одночастного и пустого отрезка', () {
    final s = chapterSegments([b(0, 'Да.')]).single;
    final r = segmentReadiness(s, p, 'pcm', (_) => false, startup: true);
    expect(r.requests.length, 1);
    expect(segmentReadiness(s, p, 'pcm', {r.requests.single.fingerprint}.contains).ready, isTrue);
    expect(segmentReadiness(SpeechSegment('', []), p, 'pcm', (_) => false).ready, isTrue);
  });

  test('хвост группы — самостоятельный; каноническая следующая группа не меняется (SC-2.1)', () {
    final blocks = [b(10, 'Раз.'), b(11, 'Два.'), b(12, 'Три.'), b(13, 'я' * 200), b(14, 'Дальше.')];
    final all = chapterSegments(blocks);
    final from = segmentsFrom(blocks, block: 11);
    expect(texts(from), ['Два.\nТри.', 'я' * 200, 'Дальше.']);
    expect(texts(from.skip(1).toList()), texts(all.skip(1).toList()));
    expect(maps(from.first), [
      [0, 4, 11, 0, 4],
      [5, 9, 12, 0, 4],
    ]);
    final whole = fingerprint(all.first.text, p, 'pcm');
    final r = segmentReadiness(from.first, p, 'pcm', {whole}.contains, startup: true);
    expect(r.ready, isFalse);
    expect(r.requests.map((u) => u.text).join(), 'Два.\nТри.');
    expect(r.requests.every((u) => u.fingerprint != whole), isTrue);
    expect(texts(segmentsFrom(blocks, block: 10)), texts(all));
  });

  test('старт с предложения внутри блока до конца его отрезка, с переводом смещения через сноску', () {
    final blocks = [
      b(0, 'Раз.1 Два. Три.', spans: [const TextSpanRange(start: 4, end: 5, style: SpanStyle.noteRef)]),
      b(1, 'Четыре.'),
      b(2, 'я' * 200),
    ];
    final from = segmentsFrom(blocks, block: 0, offset: 8);
    expect(from.first.text, 'Два. Три.\nЧетыре.');
    expect(from.first.mappings.first.blockStart, 6);
    expect(texts(segmentParts(from.first)), ['Два. Три.\nЧетыре.']);
    expect(from.last.text, 'я' * 200);
    final long = [b(0, 'Раз. Два. Три. Четыре.')];
    expect(texts(segmentsFrom(long, block: 0, offset: 11, l: 10)), ['Три. ', 'Четыре.']);
    expect(texts(segmentsFrom([b(0, '', kind: BlockKind.image), b(1, 'Текст.')], block: 0)), ['Текст.']);
    expect(segmentsFrom(long, block: 99), isEmpty);
  });

  test('инвариант: случайные входы, 10000 без пробелов, суррогаты, сноски и картинки', () {
    final random = Random(1765);
    final cases = <List<Block>>[
      [b(0, 'я' * 10000)],
      [b(0, '${'я' * 599}😀${'я' * 601}')],
      [
        b(0, '111', spans: [const TextSpanRange(start: 0, end: 3, style: SpanStyle.noteRef)]),
      ],
      [for (var i = 0; i < 20; i++) b(i, 'Подпись', kind: BlockKind.image)],
    ];
    for (var n = 0; n < 100; n++) {
      cases.add([
        for (var i = 0; i < 8; i++)
          b(
            i,
            List.generate(
              random.nextInt(250),
              (_) => ['я', ' ', '😀', 'Да. ', '\n', '\u0301'][random.nextInt(6)],
            ).join(),
            kind: BlockKind.values[random.nextInt(BlockKind.values.length)],
          ),
      ]);
    }
    for (final blocks in cases) {
      for (final l in [2, 19, 600]) {
        final segments = chapterSegments(blocks, l: l, lmin: l ~/ 3);
        final rebuilt = <int, StringBuffer>{};
        for (final s in segments) {
          expect(s.text, isNotEmpty);
          expect(s.text.length, lessThanOrEqualTo(l));
          expect(s.l, l);
          expect(s.lmin, l ~/ 3);
          expect(s.text.codeUnitAt(0), isNot(inInclusiveRange(0xdc00, 0xdfff)));
          expect(s.text.codeUnitAt(s.text.length - 1), isNot(inInclusiveRange(0xd800, 0xdbff)));
          final covered = List<bool>.filled(s.text.length, false);
          for (final m in s.mappings) {
            expect(m.end - m.start, m.blockEnd - m.blockStart);
            final source = blocks.firstWhere((b) => b.index == m.block);
            final piece = source.text.substring(m.blockStart, m.blockEnd);
            expect(piece, s.text.substring(m.start, m.end));
            (rebuilt[m.block] ??= StringBuffer()).write(piece);
            for (var j = m.start; j < m.end; j++) {
              expect(covered[j], isFalse);
              covered[j] = true;
            }
          }
          for (var j = 0; j < covered.length; j++) {
            if (!covered[j]) expect(s.text[j], '\n');
          }
          final parts = segmentParts(s);
          expect(parts.map((s) => s.text).join(), s.text);
          expect(parts.first.text.length, lessThanOrEqualTo(200));
        }
        for (final source in blocks) {
          final speech = speechText(source).text;
          final spoken = source.isSpoken && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(speech);
          expect(rebuilt[source.index]?.toString() ?? '', spoken ? speech : '');
        }
      }
    }
    expect(() => splitSpeech('😀', 1), throwsArgumentError);
    expect(() => chapterSegments([], l: 1), throwsArgumentError);
  });
}
