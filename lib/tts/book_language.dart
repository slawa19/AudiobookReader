// What in a request to Gemini depends on the language of the BOOK, not of the interface or the voice (GEMINI_TTS.md,
// "Other languages"): the reading-style text and the voice "Probe" phrase. Pure Dart.
//
// The style does not name the reader's gender: the voice may be female or male, and the grammatical gender of the word
// "рассказчица/рассказчик" would have to agree with the gender. For a language not in the table — English.

const _fallback = 'en';

/// The reading style by book language (ISO 639-1 code).
const readingStyles = <String, String>{
  'ru': 'Прочитай этот текст в манере профессиональной аудиокниги: живо, естественно, с выразительной '
      'интонацией, без лишних пауз внутри фраз.',
  'en': 'Read this text in the manner of a professional audiobook: lively, natural, with expressive intonation '
      'and no unnecessary pauses within phrases.',
  'pl': 'Przeczytaj ten tekst w stylu profesjonalnego audiobooka: żywo, naturalnie, z wyrazistą intonacją, '
      'bez zbędnych pauz wewnątrz zdań.',
  'de': 'Lies diesen Text im Stil eines professionellen Hörbuchs: lebendig, natürlich, mit ausdrucksvoller '
      'Betonung und ohne unnötige Pausen innerhalb der Sätze.',
  'uk': 'Прочитай цей текст у манері професійної аудіокниги: жваво, природно, з виразною інтонацією, '
      'без зайвих пауз усередині фраз.',
};

/// The voice "Probe" phrase by book language — the same for all voices (A§6.8), so the probe audio
/// is cached and free the second time.
const samplePhrases = <String, String>{
  'ru': 'Здравствуйте! Так будет звучать ваша книга: спокойно, ясно и с выражением.',
  'en': 'Hello! This is how your book will sound: calm, clear and expressive.',
  'pl': 'Dzień dobry! Tak będzie brzmiała twoja książka: spokojnie, wyraźnie i z wyrazem.',
  'de': 'Guten Tag! So wird Ihr Buch klingen: ruhig, klar und ausdrucksvoll.',
  'uk': 'Вітаємо! Так звучатиме ваша книга: спокійно, чітко й виразно.',
};

String _lang(String language) {
  final code = language.toLowerCase().split(RegExp('[-_]')).first;
  return samplePhrases.containsKey(code) ? code : _fallback;
}

String readingStyleFor(String bookLanguage) => readingStyles[_lang(bookLanguage)]!;

String samplePhraseFor(String bookLanguage) => samplePhrases[_lang(bookLanguage)]!;
