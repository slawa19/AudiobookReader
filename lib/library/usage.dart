/// Paid tokens of one model for a month. The library does not know the tariffs (А§2).
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
      throw const FormatException('Invalid usage counters');
    }
    return UsageTokens(audioTokens: audio, inputTokens: input);
  }
}
