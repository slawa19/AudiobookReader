/// Оплаченные токены одной модели за месяц. Тарифов библиотека не знает (А§2).
class UsageTokens {
  const UsageTokens({required this.audioTokens, required this.inputTokens});

  final int audioTokens;
  final int inputTokens;

  Map<String, Object?> toJson() => {
    'audioTokens': audioTokens,
    'inputTokens': inputTokens,
  };

  factory UsageTokens.fromJson(Map<String, Object?> json) {
    final audio = json['audioTokens'];
    final input = json['inputTokens'];
    if (audio is! int || input is! int || audio < 0 || input < 0) {
      throw const FormatException('Неверные счётчики расхода');
    }
    return UsageTokens(audioTokens: audio, inputTokens: input);
  }
}
