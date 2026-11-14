// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get shelfTitle => 'Książki';

  @override
  String get settings => 'Ustawienia';

  @override
  String get addBook => 'Dodaj książkę';

  @override
  String get continueReading => 'Kontynuuj';

  @override
  String get progressNew => 'nowa';

  @override
  String get adding => 'Dodawanie…';

  @override
  String get dismiss => 'Zamknij';

  @override
  String get emptyTitle => 'Półka jest pusta';

  @override
  String get emptyBody =>
      'Dodaj książkę FB2 lub EPUB przyciskiem „+” albo otwórz plik z innej aplikacji przez „Otwórz za pomocą”.';

  @override
  String get addFailedUnsupported => 'Ten format nie jest obsługiwany';

  @override
  String get addFailedUnreadable => 'Nie udało się odczytać książki';

  @override
  String get addFailedProtected =>
      'Książka jest zabezpieczona przed kopiowaniem i nie da się jej otworzyć';

  @override
  String get deleteNarration => 'Usuń nagranie';

  @override
  String get deleteBook => 'Usuń książkę';

  @override
  String get deleteBookTitle => 'Usunąć książkę?';

  @override
  String deleteBookBody(String title, String size) {
    return '„$title” i jej nagranie zostaną usunięte z telefonu. Zwolni się $size.';
  }

  @override
  String get deleteNarrationTitle => 'Usunąć nagranie książki?';

  @override
  String deleteNarrationBody(String title, String size) {
    return 'Dźwięk „$title” zostanie usunięty, zwolni się $size. Aby posłuchać ponownie, trzeba go nagrać i opłacić od nowa.';
  }

  @override
  String get cancel => 'Anuluj';

  @override
  String get delete => 'Usuń';

  @override
  String get pickerTitle => 'Wybór pliku';

  @override
  String get pickerNote =>
      'W prototypie to imitacja systemowego okna wyboru pliku.';

  @override
  String get back => 'Wstecz';

  @override
  String get contents => 'Spis treści';

  @override
  String get textAppearance => 'Wygląd tekstu';

  @override
  String get listen => 'Słuchaj';

  @override
  String get readFromHere => 'Czytaj stąd';

  @override
  String get toReadingPlace => 'Wróć do lektora';

  @override
  String percent(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString';
  }

  @override
  String ofBook(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString książki';
  }

  @override
  String note(String number) {
    return 'Przypis $number';
  }

  @override
  String get size => 'Rozmiar';

  @override
  String get smaller => 'Mniejszy';

  @override
  String get larger => 'Większy';

  @override
  String get theme => 'Motyw';

  @override
  String get asSystem => 'Jak w systemie';

  @override
  String get themeLight => 'Jasny';

  @override
  String get themeSepia => 'Sepia';

  @override
  String get themeDark => 'Ciemny';

  @override
  String get preparing => 'Przygotowuję głos…';

  @override
  String get waiting => 'Czekam na połączenie…';

  @override
  String get close => 'Zamknij';

  @override
  String get pause => 'Pauza';

  @override
  String get previous => 'Poprzedni akapit';

  @override
  String get next => 'Następny akapit';

  @override
  String get speed => 'Prędkość';

  @override
  String get sleepTimer => 'Wyłącznik czasowy';

  @override
  String get voice => 'Głos';

  @override
  String minutesShort(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString min';
  }

  @override
  String get endOfChapterShort => 'rozdział';

  @override
  String speedValue(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString×';
  }

  @override
  String get endOfBook => 'Koniec książki';

  @override
  String get endOfBookBody => 'Aby czytać samodzielnie, zamknij panel.';

  @override
  String get error402Title => 'Środki na koncie Gemini się skończyły';

  @override
  String get error402Body =>
      'Doładuj konto i naciśnij „Słuchaj” — wznowimy od tego akapitu.';

  @override
  String error404Title(String model) {
    return 'Model $model nie jest już dostępny';
  }

  @override
  String get error404Body => 'Wybierz inny model.';

  @override
  String get errorKeyTitle => 'Google nie przyjął klucza Gemini';

  @override
  String get errorKeyBody =>
      'Sprawdź klucz w ustawieniach i naciśnij „Słuchaj”.';

  @override
  String get changeKey => 'Zmień klucz';

  @override
  String get errorOtherTitle => 'Google odmówił nagrania';

  @override
  String google(String message) {
    return 'Google: „$message”';
  }

  @override
  String quoted(String message) {
    return '„$message”';
  }

  @override
  String get topUp => 'Doładuj';

  @override
  String get chooseModel => 'Wybierz model';

  @override
  String linkStub(String url) {
    return 'W prototypie linki się nie otwierają: $url';
  }

  @override
  String sleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuty',
      many: '$count minut',
      few: '$count minuty',
      one: '$count minuta',
    );
    return '$_temp0';
  }

  @override
  String get sleepEndOfChapter => 'Do końca rozdziału';

  @override
  String get sleepOff => 'Wyłącz';

  @override
  String sleepActive(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Pauza za $countString min';
  }

  @override
  String get sleepActiveChapter => 'Pauza na końcu rozdziału';

  @override
  String get voiced => 'nagrany';

  @override
  String notVoicedEstimate(int minutes, double price) {
    final intl.NumberFormat minutesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String minutesString = minutesNumberFormat.format(minutes);
    final intl.NumberFormat priceNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String priceString = priceNumberFormat.format(price);

    return 'Bez nagrania: ≈ $minutesString min dźwięku, ≈ $priceString';
  }

  @override
  String get downloadChapter => 'Pobierz rozdział';

  @override
  String get downloadAgain => 'Pobierz ponownie';

  @override
  String downloading(int ready, int total) {
    final intl.NumberFormat readyNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String readyString = readyNumberFormat.format(ready);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Nagrywam: gotowe $readyString z $totalString min';
  }

  @override
  String get downloadingWhileOpen => 'Działa, dopóki aplikacja jest otwarta.';

  @override
  String get stopDownload => 'Zatrzymaj';

  @override
  String downloadStrip(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return 'Pobieram rozdział · $valueString';
  }

  @override
  String get stopShort => 'Stop';

  @override
  String get downloadFailed => 'Pobieranie przerwane';

  @override
  String voiceForBook(String title) {
    return 'dla książki „$title”';
  }

  @override
  String get voiceForApp => 'dla wszystkich książek';

  @override
  String get voiceAsSettings => 'Jak w ustawieniach';

  @override
  String voiceNow(String name) {
    return 'obecnie $name';
  }

  @override
  String female(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Żeńskie · $countString';
  }

  @override
  String male(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Męskie · $countString';
  }

  @override
  String get probe => 'Próbka';

  @override
  String probeNote(String phrase) {
    return 'Próbka czyta to samo zdanie w języku książki: „$phrase” Kosztuje mniej niż cent i jest płatna raz.';
  }

  @override
  String get probeFailed => 'Próbka się nie udała';

  @override
  String get geminiKey => 'Klucz Gemini';

  @override
  String get change => 'Zmień';

  @override
  String get whereKey => 'Skąd wziąć klucz: aistudio.google.com';

  @override
  String get needKey =>
      'Aby słuchać, potrzebny jest klucz Gemini. Wpisuje się go raz i jest przechowywany tylko na telefonie.';

  @override
  String get pasteKey => 'Wklej klucz';

  @override
  String get paste => 'Wklej';

  @override
  String get model => 'Model';

  @override
  String perHour(double price) {
    final intl.NumberFormat priceNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String priceString = priceNumberFormat.format(price);

    return '$priceString za godzinę dźwięku';
  }

  @override
  String get byDefault => 'domyślny';

  @override
  String get thirdCheaper => 'o jedną trzecią taniej';

  @override
  String price2027(double a, double b) {
    final intl.NumberFormat aNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String aString = aNumberFormat.format(a);
    final intl.NumberFormat bNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String bString = bNumberFormat.format(b);

    return 'Od 1 stycznia 2027 roku Google pobiera dwa razy więcej: $aString i $bString za godzinę. Dźwięk jednego modelu nie liczy się dla drugiego: po zmianie książki są nagrywane od nowa.';
  }

  @override
  String get spent => 'Wydano';

  @override
  String money(double amount) {
    final intl.NumberFormat amountNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String amountString = amountNumberFormat.format(amount);

    return '$amountString';
  }

  @override
  String get storage => 'Nagrania na telefonie';

  @override
  String get clear => 'Wyczyść';

  @override
  String get storageNote =>
      'Za nagrany dźwięk nie płaci się drugi raz. Po wyczyszczeniu trzeba go nagrać i opłacić od nowa.';

  @override
  String get clearTitle => 'Wyczyścić nagrania?';

  @override
  String clearBody(String size) {
    return 'Usunięte zostanie $size dźwięku wszystkich książek i próbek głosu. Aby posłuchać ponownie, trzeba go nagrać i opłacić od nowa.';
  }

  @override
  String megabytes(int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString MB';
  }

  @override
  String gigabytes(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString GB';
  }

  @override
  String get language => 'Język';

  @override
  String get langRu => 'Русский';

  @override
  String get langEn => 'English';

  @override
  String get langPl => 'Polski';

  @override
  String get langDe => 'Deutsch';

  @override
  String get voiceCharSoft => 'miękki';

  @override
  String get voiceCharBreezy => 'lekki';

  @override
  String get voiceCharBright => 'jasny';

  @override
  String get voiceCharCalm => 'spokojny';

  @override
  String get voiceCharSmooth => 'płynny';

  @override
  String get voiceCharClear => 'wyraźny';

  @override
  String get voiceCharMature => 'dojrzały';

  @override
  String get voiceCharFirm => 'stanowczy';

  @override
  String get voiceCharUpbeat => 'pogodny';

  @override
  String get voiceCharYouthful => 'młodzieńczy';

  @override
  String get voiceCharForward => 'śmiały';

  @override
  String get voiceCharWarm => 'ciepły';

  @override
  String get voiceCharGentle => 'łagodny';

  @override
  String get voiceCharFriendly => 'przyjazny';

  @override
  String get voiceCharGravelly => 'chropawy';

  @override
  String get voiceCharInformative => 'rzeczowy';

  @override
  String get voiceCharBreathy => 'z przydechem';

  @override
  String get voiceCharExcitable => 'pobudzony';

  @override
  String get voiceCharLively => 'żywy';

  @override
  String get voiceCharKnowledgeable => 'kompetentny';

  @override
  String get voiceCharEven => 'równy';

  @override
  String get voiceCharEasygoing => 'swobodny';

  @override
  String get voiceCharConversational => 'rozmowny';
}
