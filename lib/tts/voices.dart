// Голоса и модели Gemini TTS. Набор голосов и тарифы — docs/GEMINI_TTS.md. Чистый Dart.

class Voice {
  const Voice(this.name, this.character, {required this.female});

  final String name;
  final String character;
  final bool female;
}

const defaultVoiceName = 'Aoede';

const allVoices = <Voice>[
  Voice('Achernar', 'мягкий', female: true),
  Voice('Aoede', 'лёгкий, непринуждённый', female: true),
  Voice('Autonoe', 'яркий', female: true),
  Voice('Callirrhoe', 'спокойный', female: true),
  Voice('Despina', 'плавный', female: true),
  Voice('Erinome', 'чёткий', female: true),
  Voice('Gacrux', 'зрелый', female: true),
  Voice('Kore', 'твёрдый', female: true),
  Voice('Laomedeia', 'бодрый', female: true),
  Voice('Leda', 'молодой', female: true),
  Voice('Pulcherrima', 'напористый', female: true),
  Voice('Sulafat', 'тёплый', female: true),
  Voice('Vindemiatrix', 'нежный', female: true),
  Voice('Zephyr', 'яркий', female: true),
  Voice('Achird', 'дружелюбный', female: false),
  Voice('Algenib', 'с хрипотцой', female: false),
  Voice('Algieba', 'плавный', female: false),
  Voice('Alnilam', 'твёрдый', female: false),
  Voice('Charon', 'деловой', female: false),
  Voice('Enceladus', 'с придыханием', female: false),
  Voice('Fenrir', 'возбуждённый', female: false),
  Voice('Iapetus', 'чёткий', female: false),
  Voice('Orus', 'твёрдый', female: false),
  Voice('Puck', 'бодрый', female: false),
  Voice('Rasalgethi', 'деловой', female: false),
  Voice('Sadachbia', 'живой', female: false),
  Voice('Sadaltager', 'знающий', female: false),
  Voice('Schedar', 'ровный', female: false),
  Voice('Umbriel', 'непринуждённый', female: false),
  Voice('Zubenelgenubi', 'разговорный', female: false),
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

/// Секунд звука на знак текста — верх замера (GEMINI_TTS.md, «Цена»).
const secondsPerChar = 0.069;
