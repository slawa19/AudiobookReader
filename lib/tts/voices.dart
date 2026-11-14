// Голоса и модели Gemini TTS. Набор голосов и тарифы — docs/GEMINI_TTS.md. Чистый Dart.

/// Характер голоса. Подпись на языке интерфейса даёт экран (строки — в ARB); здесь только ключ.
/// Ключи следуют русским описаниям из GEMINI_TTS.md: где Google называет два голоса одним словом, а русское
/// описание различается («спокойный» и «непринуждённый»), ключей два.
enum VoiceCharacter {
  soft,
  breezy,
  bright,
  calm,
  smooth,
  clear,
  mature,
  firm,
  upbeat,
  youthful,
  forward,
  warm,
  gentle,
  friendly,
  gravelly,
  informative,
  breathy,
  excitable,
  lively,
  knowledgeable,
  even,
  easygoing,
  conversational,
}

class Voice {
  const Voice(this.name, this.character, {required this.female});

  final String name;
  final VoiceCharacter character;
  final bool female;
}

const defaultVoiceName = 'Aoede';

const allVoices = <Voice>[
  Voice('Achernar', VoiceCharacter.soft, female: true),
  Voice('Aoede', VoiceCharacter.breezy, female: true),
  Voice('Autonoe', VoiceCharacter.bright, female: true),
  Voice('Callirrhoe', VoiceCharacter.calm, female: true),
  Voice('Despina', VoiceCharacter.smooth, female: true),
  Voice('Erinome', VoiceCharacter.clear, female: true),
  Voice('Gacrux', VoiceCharacter.mature, female: true),
  Voice('Kore', VoiceCharacter.firm, female: true),
  Voice('Laomedeia', VoiceCharacter.upbeat, female: true),
  Voice('Leda', VoiceCharacter.youthful, female: true),
  Voice('Pulcherrima', VoiceCharacter.forward, female: true),
  Voice('Sulafat', VoiceCharacter.warm, female: true),
  Voice('Vindemiatrix', VoiceCharacter.gentle, female: true),
  Voice('Zephyr', VoiceCharacter.bright, female: true),
  Voice('Achird', VoiceCharacter.friendly, female: false),
  Voice('Algenib', VoiceCharacter.gravelly, female: false),
  Voice('Algieba', VoiceCharacter.smooth, female: false),
  Voice('Alnilam', VoiceCharacter.firm, female: false),
  Voice('Charon', VoiceCharacter.informative, female: false),
  Voice('Enceladus', VoiceCharacter.breathy, female: false),
  Voice('Fenrir', VoiceCharacter.excitable, female: false),
  Voice('Iapetus', VoiceCharacter.clear, female: false),
  Voice('Orus', VoiceCharacter.firm, female: false),
  Voice('Puck', VoiceCharacter.upbeat, female: false),
  Voice('Rasalgethi', VoiceCharacter.informative, female: false),
  Voice('Sadachbia', VoiceCharacter.lively, female: false),
  Voice('Sadaltager', VoiceCharacter.knowledgeable, female: false),
  Voice('Schedar', VoiceCharacter.even, female: false),
  Voice('Umbriel', VoiceCharacter.easygoing, female: false),
  Voice('Zubenelgenubi', VoiceCharacter.conversational, female: false),
];

Voice voiceByName(String name) => allVoices.firstWhere((v) => v.name == name, orElse: () => allVoices[1]);

enum TtsModel {
  flash('gemini-3.8-flash-tts', '3.8 Flash', 0.81, 1.62),
  flashLite('gemini-3.8-flash-lite-tts', '3.8 Flash-Lite', 0.54, 1.08);

  const TtsModel(this.id, this.label, this.dollarsPerHourNow, this.dollarsPerHourFrom2027);

  static TtsModel byId(String id) => TtsModel.values.firstWhere((m) => m.id == id, orElse: () => TtsModel.flash);

  final String id;
  final String label;
  final double dollarsPerHourNow;
  final double dollarsPerHourFrom2027;

  /// Тариф на дату (FR-M1): смена 01.01.2027.
  double dollarsPerHourAt(DateTime date) =>
      date.isBefore(DateTime(2027)) ? dollarsPerHourNow : dollarsPerHourFrom2027;
}

/// Профиль голоса (А§6.2): то, от чего зависит звук. Готовность главы и оценка остатка считаются для
/// действующего профиля: звук другим голосом или моделью для него не годится. Стиль в прототипе один — по языку
/// книги, и он не меняется у книги, поэтому здесь его нет.
class VoiceProfile {
  const VoiceProfile({required this.voice, required this.modelId});

  final String voice;
  final String modelId;

  String get key => '$voice/$modelId';

  @override
  bool operator ==(Object other) => other is VoiceProfile && other.voice == voice && other.modelId == modelId;

  @override
  int get hashCode => Object.hash(voice, modelId);

  @override
  String toString() => 'VoiceProfile($voice, $modelId)';
}

/// Секунд звука на знак текста — верх замера (GEMINI_TTS.md, «Цена»).
const secondsPerChar = 0.069;
