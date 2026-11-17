// Что в запросе к Gemini зависит от языка КНИГИ, а не интерфейса и не голоса (GEMINI_TTS.md, «Другие языки»):
// текст стиля чтения и фраза «Пробы». Чистый Dart.
//
// Стиль не называет пол чтеца: голос может быть и женским, и мужским, а род слова «рассказчица/рассказчик»
// согласовывался бы с полом. Для языка, которого нет в таблице, — английский.

const _fallback = 'en';

/// Стиль чтения по языку книги (код ISO 639-1).
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

/// Фраза «Пробы» голоса по языку книги — одна и та же для всех голосов (А§6.8), поэтому звук пробы
/// кэшируется и второй раз бесплатен.
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
