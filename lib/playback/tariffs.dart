import '../tts/voices.dart';

/// Цена по тарифу на сегодня (FR-V3, FR-M1). Дату даёт корень сборки: экраны тарифов и дат не знают и получают
/// готовые числа.
class Tariffs {
  Tariffs({required this.today});

  final DateTime Function() today;

  double dollarsPerHour(TtsModel model) => model.dollarsPerHourAt(today());

  /// До 01.01.2027 настройки предупреждают о будущем удвоении цены.
  bool get beforePriceChange => today().isBefore(DateTime(2027));
}
