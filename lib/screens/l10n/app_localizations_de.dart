// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get mediaChannel => 'Buchwiedergabe';

  @override
  String get mediaPrevious => 'Vorheriger Abschnitt';

  @override
  String get mediaNext => 'Nächster Abschnitt';

  @override
  String get shelfTitle => 'Bücher';

  @override
  String get settings => 'Einstellungen';

  @override
  String get fakeVoice => 'Teststimme';

  @override
  String get addBook => 'Buch hinzufügen';

  @override
  String get continueReading => 'Weiterlesen';

  @override
  String get progressNew => 'neu';

  @override
  String get adding => 'Wird hinzugefügt…';

  @override
  String get dismiss => 'Ausblenden';

  @override
  String get emptyTitle => 'Das Regal ist leer';

  @override
  String get emptyBody =>
      'Mit „+“ ein Buch als FB2 oder EPUB hinzufügen – oder eine Datei aus einer anderen App über „Öffnen mit“ öffnen.';

  @override
  String get addFailedUnsupported => 'Dieses Format wird nicht unterstützt';

  @override
  String get addFailedUnreadable => 'Das Buch konnte nicht gelesen werden';

  @override
  String get addFailedProtected =>
      'Das Buch ist kopiergeschützt und lässt sich nicht öffnen';

  @override
  String get deleteNarration => 'Vertonung löschen';

  @override
  String get deleteBook => 'Buch löschen';

  @override
  String get deleteBookTitle => 'Buch löschen?';

  @override
  String deleteBookBody(String title, String size) {
    return '„$title“ und die Vertonung werden vom Telefon gelöscht. Das gibt $size frei.';
  }

  @override
  String get deleteNarrationTitle => 'Vertonung des Buchs löschen?';

  @override
  String deleteNarrationBody(String title, String size) {
    return 'Der Ton von „$title“ wird gelöscht und gibt $size frei. Zum erneuten Anhören muss er neu vertont und bezahlt werden.';
  }

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get pickerTitle => 'Datei auswählen';

  @override
  String get pickerNote =>
      'Im Prototyp wird die Dateiauswahl des Systems nachgebildet.';

  @override
  String get back => 'Zurück';

  @override
  String get contents => 'Inhaltsverzeichnis';

  @override
  String get textAppearance => 'Textdarstellung';

  @override
  String get listen => 'Anhören';

  @override
  String get readFromHere => 'Ab hier lesen';

  @override
  String get toReadingPlace => 'Zur aktuellen Stelle';

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

    return '$valueString des Buchs';
  }

  @override
  String note(String number) {
    return 'Anmerkung $number';
  }

  @override
  String get size => 'Größe';

  @override
  String get smaller => 'Kleiner';

  @override
  String get larger => 'Größer';

  @override
  String get theme => 'Design';

  @override
  String get asSystem => 'Systemstandard';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeSepia => 'Sepia';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get preparing => 'Stimme wird vorbereitet…';

  @override
  String get waiting => 'Warten auf Verbindung…';

  @override
  String get close => 'Schließen';

  @override
  String get pause => 'Pause';

  @override
  String get previous => 'Vorheriger Absatz';

  @override
  String get next => 'Nächster Absatz';

  @override
  String get speed => 'Tempo';

  @override
  String get sleepTimer => 'Schlaftimer';

  @override
  String get voice => 'Stimme';

  @override
  String minutesShort(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString Min.';
  }

  @override
  String get endOfChapterShort => 'Kapitel';

  @override
  String speedValue(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString×';
  }

  @override
  String get endOfBook => 'Das Buch ist zu Ende';

  @override
  String get endOfBookBody => 'Um selbst zu lesen, das Bedienfeld schließen.';

  @override
  String get error402Title => 'Das Gemini-Guthaben ist aufgebraucht';

  @override
  String get error402Body =>
      'Guthaben aufladen und auf „Anhören“ tippen – dann geht es ab diesem Absatz weiter.';

  @override
  String error404Title(String model) {
    return 'Das Modell $model ist nicht mehr verfügbar';
  }

  @override
  String get error404Body => 'Anderes Modell wählen.';

  @override
  String get errorKeyTitle =>
      'Google hat den Gemini-Schlüssel nicht akzeptiert';

  @override
  String get errorKeyBody =>
      'Schlüssel in den Einstellungen prüfen und auf „Anhören“ tippen.';

  @override
  String get changeKey => 'Schlüssel ändern';

  @override
  String get errorOtherTitle => 'Google hat die Vertonung abgelehnt';

  @override
  String google(String message) {
    return 'Google: „$message“';
  }

  @override
  String quoted(String message) {
    return '„$message“';
  }

  @override
  String get topUp => 'Aufladen';

  @override
  String get chooseModel => 'Modell wählen';

  @override
  String linkStub(String url) {
    return 'Im Prototyp öffnen sich keine Links: $url';
  }

  @override
  String sleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '$count Minute',
    );
    return '$_temp0';
  }

  @override
  String get sleepEndOfChapter => 'Bis zum Kapitelende';

  @override
  String get sleepOff => 'Ausschalten';

  @override
  String sleepActive(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Pause in $countString Min.';
  }

  @override
  String get sleepActiveChapter => 'Pause am Kapitelende';

  @override
  String get voiced => 'vertont';

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

    return 'Nicht vertont: ≈ $minutesString Min. Ton, ≈ $priceString';
  }

  @override
  String get downloadChapter => 'Kapitel herunterladen';

  @override
  String get downloadAgain => 'Erneut herunterladen';

  @override
  String downloading(int ready, int total) {
    final intl.NumberFormat readyNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String readyString = readyNumberFormat.format(ready);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Wird vertont: $readyString von $totalString Min. fertig';
  }

  @override
  String get downloadingWhileOpen => 'Läuft, solange die App geöffnet ist.';

  @override
  String get stopDownload => 'Anhalten';

  @override
  String downloadStrip(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return 'Kapitel wird geladen · $valueString';
  }

  @override
  String get stopShort => 'Stopp';

  @override
  String get downloadFailed => 'Download abgebrochen';

  @override
  String voiceForBook(String title) {
    return 'für „$title“';
  }

  @override
  String get voiceForApp => 'für alle Bücher';

  @override
  String get voiceAsSettings => 'Wie in den Einstellungen';

  @override
  String voiceNow(String name) {
    return 'derzeit $name';
  }

  @override
  String female(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Weiblich · $countString';
  }

  @override
  String male(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Männlich · $countString';
  }

  @override
  String get probe => 'Hörprobe';

  @override
  String probeNote(String phrase) {
    return 'Die Hörprobe liest immer denselben Satz in der Sprache des Buchs: „$phrase“ Sie kostet weniger als einen Cent und wird einmal bezahlt.';
  }

  @override
  String get probeFailed => 'Hörprobe fehlgeschlagen';

  @override
  String get geminiKey => 'Gemini-Schlüssel';

  @override
  String get change => 'Ändern';

  @override
  String get whereKey => 'Schlüssel holen: aistudio.google.com';

  @override
  String get needKey =>
      'Zum Anhören ist ein Gemini-Schlüssel nötig. Er wird einmal eingegeben und nur auf dem Telefon gespeichert.';

  @override
  String get pasteKey => 'Schlüssel einfügen';

  @override
  String get paste => 'Einfügen';

  @override
  String get model => 'Modell';

  @override
  String perHour(double price) {
    final intl.NumberFormat priceNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String priceString = priceNumberFormat.format(price);

    return '$priceString pro Stunde Ton';
  }

  @override
  String get byDefault => 'Standard';

  @override
  String get thirdCheaper => 'ein Drittel günstiger';

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

    return 'Ab 1. Januar 2027 verlangt Google das Doppelte: $aString und $bString pro Stunde. Ton, der mit einem Modell vertont wurde, lässt sich beim anderen nicht wiederverwenden: Nach einem Wechsel werden Bücher neu vertont.';
  }

  @override
  String get spent => 'Ausgegeben';

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
  String get storage => 'Vertonung auf dem Telefon';

  @override
  String get clear => 'Leeren';

  @override
  String get storageNote =>
      'Vertonter Ton wird nicht zweimal bezahlt. Nach dem Leeren muss er neu vertont und bezahlt werden.';

  @override
  String get licenses => 'Open-Source-Lizenzen';

  @override
  String get clearTitle => 'Vertonung leeren?';

  @override
  String clearBody(String size) {
    return '$size Ton aller Bücher und Hörproben werden gelöscht. Zum erneuten Anhören muss er neu vertont und bezahlt werden.';
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
  String get language => 'Sprache';

  @override
  String get langRu => 'Русский';

  @override
  String get langEn => 'English';

  @override
  String get langPl => 'Polski';

  @override
  String get langDe => 'Deutsch';

  @override
  String get langUk => 'Українська';

  @override
  String get voiceCharSoft => 'weich';

  @override
  String get voiceCharBreezy => 'leicht';

  @override
  String get voiceCharBright => 'hell';

  @override
  String get voiceCharCalm => 'ruhig';

  @override
  String get voiceCharSmooth => 'geschmeidig';

  @override
  String get voiceCharClear => 'klar';

  @override
  String get voiceCharMature => 'reif';

  @override
  String get voiceCharFirm => 'bestimmt';

  @override
  String get voiceCharUpbeat => 'munter';

  @override
  String get voiceCharYouthful => 'jugendlich';

  @override
  String get voiceCharForward => 'forsch';

  @override
  String get voiceCharWarm => 'warm';

  @override
  String get voiceCharGentle => 'sanft';

  @override
  String get voiceCharFriendly => 'freundlich';

  @override
  String get voiceCharGravelly => 'rau';

  @override
  String get voiceCharInformative => 'sachlich';

  @override
  String get voiceCharBreathy => 'gehaucht';

  @override
  String get voiceCharExcitable => 'aufgeregt';

  @override
  String get voiceCharLively => 'lebhaft';

  @override
  String get voiceCharKnowledgeable => 'sachkundig';

  @override
  String get voiceCharEven => 'gleichmäßig';

  @override
  String get voiceCharEasygoing => 'entspannt';

  @override
  String get voiceCharConversational => 'gesprächig';
}
