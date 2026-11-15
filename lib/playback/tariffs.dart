import '../tts/voices.dart';
import '../library/library.dart';

/// Две суммы для AppServices.spentByMonth; каждый месяц оплачивается по своему тарифу.
List<({DateTime month, double dollars})> spentByMonth(
  Library library,
  DateTime today,
) => [
  for (final month in [
    DateTime(today.year, today.month),
    DateTime(today.year, today.month - 1),
  ])
    (
      month: month,
      dollars: (library.usage[month] ?? {}).entries.fold<double>(
        0,
        (sum, entry) =>
            sum +
            TtsModel.byId(entry.key).dollarsForTokensAt(
              audioTokens: entry.value.audioTokens,
              inputTokens: entry.value.inputTokens,
              date: month,
            ),
      ),
    ),
];

/// Цена по тарифу на сегодня (FR-V3, FR-M1). Дату даёт корень сборки: экраны тарифов и дат не знают и получают
/// готовые числа.
class Tariffs {
  Tariffs({required this.today});

  final DateTime Function() today;

  double dollarsPerHour(TtsModel model) => model.dollarsPerHourAt(today());

  /// До 01.01.2027 настройки предупреждают о будущем удвоении цены.
  bool get beforePriceChange => today().isBefore(DateTime(2027));
}
