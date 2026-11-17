import '../tts/voices.dart';
import '../library/library.dart';

/// Two amounts for AppServices.spentByMonth; each month is paid at its own tariff.
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

/// The price at today's tariff (FR-V3, FR-M1). The date is supplied by the assembly root: screens know neither tariffs
/// nor dates and receive ready numbers.
class Tariffs {
  Tariffs({required this.today});

  final DateTime Function() today;

  double dollarsPerHour(TtsModel model) => model.dollarsPerHourAt(today());

  /// Until 2027-01-01 the settings warn about the future doubling of the price.
  bool get beforePriceChange => today().isBefore(DateTime(2027));
}
