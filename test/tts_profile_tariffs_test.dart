import 'dart:convert';

import 'package:audiobook_reader/tts/book_language.dart';
import 'package:audiobook_reader/tts/fingerprint.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FR-T3: sorted UTF-8 JSON; every field and the format change the sha256', () {
    const p = VoiceProfile(model: 'm', voiceId: 'v', style: 's');
    final fp = fingerprint('Речь', p, 'pcm');
    expect(
      fp,
      sha256.convert(utf8.encode('{"format":"pcm","model":"m","style":"s","text":"Речь","voice_id":"v"}')).toString(),
    );
    expect(fp, matches(RegExp(r'^[a-f0-9]{64}$')));
    final changed = [
      fingerprint('Иное', p, 'pcm'),
      fingerprint('Речь', p, 'aac'),
      fingerprint('Речь', const VoiceProfile(model: 'M', voiceId: 'v', style: 's'), 'pcm'),
      fingerprint('Речь', const VoiceProfile(model: 'm', voiceId: 'V', style: 's'), 'pcm'),
      fingerprint('Речь', const VoiceProfile(model: 'm', voiceId: 'v', style: 'S'), 'pcm'),
    ];
    expect(changed.toSet().length, 5);
    expect(changed, everyElement(isNot(fp)));
    expect(fingerprint('Ре\u0301чь', p, 'pcm'), fingerprint('Речь', p, 'pcm'));
    expect(p, const VoiceProfile(voiceId: 'v', model: 'm', style: 's'));
    expect(p.key, isNot(const VoiceProfile(model: 'm', voiceId: 'v', style: 'S').key));
  });

  test('FR-T7: five languages and a fallback, style is gender-neutral and independent of voice gender', () {
    expect(readingStyles.keys.toSet(), {'ru', 'en', 'pl', 'de', 'uk'});
    expect(samplePhrases.keys.toSet(), {'ru', 'en', 'pl', 'de', 'uk'});
    final styles = <String>{};
    final samples = <String>{};
    final hashes = <String>{};
    for (final language in ['ru', 'en', 'pl', 'de', 'uk']) {
      final style = readingStyleFor(language);
      expect(style, readingStyles[language]);
      expect(samplePhraseFor(language), samplePhrases[language]);
      expect(style, isNot(contains(RegExp('рассказчик|рассказчиц|narrator|narratorka|Sprecher'))));
      styles.add(style);
      samples.add(samplePhraseFor(language));
      for (final voice in ['Aoede', 'Charon']) {
        final p = VoiceProfile(model: TtsModel.flash.id, voiceId: voice, style: readingStyleFor(language));
        expect(p.style, style);
      }
      hashes.add(fingerprint('Один текст', VoiceProfile(model: 'm', voiceId: 'v', style: style), 'aac'));
    }
    expect(styles.length, 5);
    expect(samples.length, 5);
    expect(hashes.length, 5);
    for (final unknown in ['', 'cs', 'fr-FR']) {
      expect(readingStyleFor(unknown), readingStyles['en']);
      expect(samplePhraseFor(unknown), samplePhrases['en']);
    }
    expect(readingStyleFor('RU-ru'), readingStyles['ru']);
    expect(readingStyleFor('uk-UA'), readingStyles['uk']);
    expect(samplePhraseFor('uk_UA'), samplePhrases['uk']);
    expect(samplePhraseFor('pl_PL'), samplePhrases['pl']);
  });

  test('FR-M1/V3: uniform tariffs before and from 01.01.2027, input and output, verification date and estimate', () {
    expect(tariffVerifiedOn, '2026-11-11');
    expect(tariffChangesOn, '2027-01-01');
    expect(secondsPerChar, 0.069);
    expect(audioTokensPerSecond, 25);
    for (final (model, before, after, audio) in [
      (TtsModel.flash, 0.81, 1.62, 9.0),
      (TtsModel.flashLite, 0.54, 1.08, 6.0),
    ]) {
      for (final (date, factor, hour) in [
        (DateTime(2026, 12, 31, 23, 59, 59), 1, before),
        (DateTime(2027), 2, after),
        (DateTime.utc(2027), 2, after),
      ]) {
        expect(model.dollarsPerHourAt(date), closeTo(hour, 1e-12));
        expect(model.audioDollarsPerMillionAt(date), audio * factor);
        expect(model.inputDollarsPerMillionAt(date), 0.5 * factor);
        expect(
          model.dollarsForTokensAt(audioTokens: 1000000, inputTokens: 1000000, date: date),
          (audio + 0.5) * factor,
        );
        expect(model.dollarsForTokensAt(audioTokens: 90000, date: date), closeTo(hour, 1e-12));
      }
    }
  });
}
