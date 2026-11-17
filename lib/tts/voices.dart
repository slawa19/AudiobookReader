// Gemini TTS voices and models. The voice set and tariffs — docs/GEMINI_TTS.md. Pure Dart.

/// The voice character. The label in the interface language is provided by the screen (strings are in the ARB); only
/// the key is here. The keys follow the descriptions in GEMINI_TTS.md, "Voices": where Google names two voices with one
/// word ("easy-going") but the descriptions there differ ("calm" and "easygoing"), there are two keys.
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
  flash('gemini-3.8-flash-tts', '3.8 Flash', 9),
  flashLite('gemini-3.8-flash-lite-tts', '3.8 Flash-Lite', 6);

  const TtsModel(this.id, this.label, this.audioDollarsPerMillionNow);

  static TtsModel byId(String id) => TtsModel.values.firstWhere((m) => m.id == id, orElse: () => TtsModel.flash);

  final String id;
  final String label;
  final double audioDollarsPerMillionNow;
  double get dollarsPerHourNow => audioDollarsPerMillionNow * audioTokensPerSecond * 3600 / 1000000;
  double get dollarsPerHourFrom2027 => dollarsPerHourNow * 2;

  double audioDollarsPerMillionAt(DateTime date) => audioDollarsPerMillionNow * _tariffMultiplier(date);
  double inputDollarsPerMillionAt(DateTime date) => 0.5 * _tariffMultiplier(date);

  double dollarsForTokensAt({required int audioTokens, int inputTokens = 0, required DateTime date}) =>
      (audioTokens * audioDollarsPerMillionAt(date) + inputTokens * inputDollarsPerMillionAt(date)) / 1000000;

  /// The tariff for a date (FR-M1): changes on 2027-01-01.
  double dollarsPerHourAt(DateTime date) => dollarsPerHourNow * _tariffMultiplier(date);
}

/// The full audio profile.
class VoiceProfile {
  const VoiceProfile({required this.voiceId, required this.model, this.style = ''});

  final String voiceId;
  final String model;
  final String style;

  String get key => '${voiceId.length}:$voiceId${model.length}:$model${style.length}:$style';

  @override
  bool operator ==(Object other) =>
      other is VoiceProfile && other.voiceId == voiceId && other.model == model && other.style == style;

  @override
  int get hashCode => Object.hash(voiceId, model, style);

  @override
  String toString() => 'VoiceProfile($voiceId, $model, $style)';
}

/// Tariff dates from GEMINI_TTS.md; a calendar date in the time zone of the passed value.
const tariffVerifiedOn = '2026-11-11';
const tariffChangeYear = 2027;
const tariffChangesOn = '$tariffChangeYear-01-01';
double _tariffMultiplier(DateTime date) => date.year < tariffChangeYear ? 1 : 2;
const audioTokensPerSecond = 25;

/// Seconds of audio per text character — the top of the measurement (GEMINI_TTS.md, "Price").
const secondsPerChar = 0.069;
