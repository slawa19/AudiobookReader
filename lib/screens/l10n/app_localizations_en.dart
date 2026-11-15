// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get mediaChannel => 'Book playback';

  @override
  String get mediaPrevious => 'Previous segment';

  @override
  String get mediaNext => 'Next segment';

  @override
  String get shelfTitle => 'Books';

  @override
  String get settings => 'Settings';

  @override
  String get fakeVoice => 'Fake voice';

  @override
  String get addBook => 'Add book';

  @override
  String get continueReading => 'Continue';

  @override
  String get progressNew => 'new';

  @override
  String get adding => 'Adding…';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get emptyTitle => 'Your shelf is empty';

  @override
  String get emptyBody =>
      'Add an FB2 or EPUB book with the “+” button, or open a file from another app with “Open with”.';

  @override
  String get addFailedUnsupported => 'This format is not supported';

  @override
  String get addFailedUnreadable => 'Couldn’t read the book';

  @override
  String get addFailedProtected =>
      'The book is copy-protected and can’t be opened';

  @override
  String get deleteNarration => 'Delete narration';

  @override
  String get deleteBook => 'Delete book';

  @override
  String get deleteBookTitle => 'Delete the book?';

  @override
  String deleteBookBody(String title, String size) {
    return '“$title” and its narration will be removed from the phone. This frees $size.';
  }

  @override
  String get deleteNarrationTitle => 'Delete the book’s narration?';

  @override
  String deleteNarrationBody(String title, String size) {
    return 'The audio of “$title” will be deleted, freeing $size. To listen again, it has to be narrated and paid for again.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get pickerTitle => 'Choose a file';

  @override
  String get pickerNote =>
      'In the prototype this imitates the system file picker.';

  @override
  String get back => 'Back';

  @override
  String get contents => 'Contents';

  @override
  String get textAppearance => 'Text appearance';

  @override
  String get listen => 'Listen';

  @override
  String get readFromHere => 'Read from here';

  @override
  String get toReadingPlace => 'To current spot';

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

    return '$valueString of the book';
  }

  @override
  String note(String number) {
    return 'Note $number';
  }

  @override
  String get size => 'Size';

  @override
  String get smaller => 'Smaller';

  @override
  String get larger => 'Larger';

  @override
  String get theme => 'Theme';

  @override
  String get asSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSepia => 'Sepia';

  @override
  String get themeDark => 'Dark';

  @override
  String get preparing => 'Preparing the voice…';

  @override
  String get waiting => 'Waiting for connection…';

  @override
  String get close => 'Close';

  @override
  String get pause => 'Pause';

  @override
  String get previous => 'Previous paragraph';

  @override
  String get next => 'Next paragraph';

  @override
  String get speed => 'Speed';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get voice => 'Voice';

  @override
  String minutesShort(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString min';
  }

  @override
  String get endOfChapterShort => 'chapter';

  @override
  String speedValue(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString×';
  }

  @override
  String get endOfBook => 'End of the book';

  @override
  String get endOfBookBody => 'To read it yourself, close the panel.';

  @override
  String get error402Title => 'Your Gemini balance is empty';

  @override
  String get error402Body =>
      'Top up your balance and tap “Listen” — we’ll continue from this paragraph.';

  @override
  String error404Title(String model) {
    return 'The $model model is no longer available';
  }

  @override
  String get error404Body => 'Choose another model.';

  @override
  String get errorKeyTitle => 'Google did not accept your Gemini key';

  @override
  String get errorKeyBody => 'Check the key in Settings and tap “Listen”.';

  @override
  String get changeKey => 'Change key';

  @override
  String get errorOtherTitle => 'Google refused to narrate';

  @override
  String google(String message) {
    return 'Google: “$message”';
  }

  @override
  String quoted(String message) {
    return '“$message”';
  }

  @override
  String get topUp => 'Top up';

  @override
  String get chooseModel => 'Choose model';

  @override
  String linkStub(String url) {
    return 'Links don’t open in the prototype: $url';
  }

  @override
  String sleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '$count minute',
    );
    return '$_temp0';
  }

  @override
  String get sleepEndOfChapter => 'Until the end of the chapter';

  @override
  String get sleepOff => 'Turn off';

  @override
  String sleepActive(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Pause in $countString min';
  }

  @override
  String get sleepActiveChapter => 'Pause at the end of the chapter';

  @override
  String get voiced => 'narrated';

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

    return 'Not narrated: ≈ $minutesString min of audio, ≈ $priceString';
  }

  @override
  String get downloadChapter => 'Download chapter';

  @override
  String get downloadAgain => 'Download again';

  @override
  String downloading(int ready, int total) {
    final intl.NumberFormat readyNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String readyString = readyNumberFormat.format(ready);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Narrating: $readyString of $totalString min ready';
  }

  @override
  String get downloadingWhileOpen => 'Runs while the app is open.';

  @override
  String get stopDownload => 'Stop';

  @override
  String downloadStrip(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return 'Downloading chapter · $valueString';
  }

  @override
  String get stopShort => 'Stop';

  @override
  String get downloadFailed => 'Download stopped';

  @override
  String voiceForBook(String title) {
    return 'for “$title”';
  }

  @override
  String get voiceForApp => 'for all books';

  @override
  String get voiceAsSettings => 'Same as in Settings';

  @override
  String voiceNow(String name) {
    return 'currently $name';
  }

  @override
  String female(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Female · $countString';
  }

  @override
  String male(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Male · $countString';
  }

  @override
  String get probe => 'Sample';

  @override
  String probeNote(String phrase) {
    return 'The sample reads the same phrase in the book’s language: “$phrase” It costs less than a cent, and you pay for it only once.';
  }

  @override
  String get probeFailed => 'Sample failed';

  @override
  String get geminiKey => 'Gemini key';

  @override
  String get change => 'Change';

  @override
  String get whereKey => 'Get a key: aistudio.google.com';

  @override
  String get needKey =>
      'To listen, you need a Gemini key. You enter it once, and it is stored only on this phone.';

  @override
  String get pasteKey => 'Paste the key';

  @override
  String get paste => 'Paste';

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

    return '$priceString per hour of audio';
  }

  @override
  String get byDefault => 'default';

  @override
  String get thirdCheaper => 'a third cheaper';

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

    return 'Starting January 1, 2027, Google charges twice as much: $aString and $bString per hour. Audio narrated with one model can’t be reused with the other, so after switching, books are narrated again.';
  }

  @override
  String get spent => 'Spent';

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
  String get storage => 'Narration on this phone';

  @override
  String get clear => 'Clear';

  @override
  String get storageNote =>
      'Narrated audio is not paid for twice. After clearing, it has to be narrated and paid for again.';

  @override
  String get clearTitle => 'Clear narration?';

  @override
  String clearBody(String size) {
    return '$size of audio for all books and voice samples will be deleted. To listen again, it has to be narrated and paid for again.';
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
  String get language => 'Language';

  @override
  String get langRu => 'Русский';

  @override
  String get langEn => 'English';

  @override
  String get langPl => 'Polski';

  @override
  String get langDe => 'Deutsch';

  @override
  String get voiceCharSoft => 'soft';

  @override
  String get voiceCharBreezy => 'breezy';

  @override
  String get voiceCharBright => 'bright';

  @override
  String get voiceCharCalm => 'calm';

  @override
  String get voiceCharSmooth => 'smooth';

  @override
  String get voiceCharClear => 'clear';

  @override
  String get voiceCharMature => 'mature';

  @override
  String get voiceCharFirm => 'firm';

  @override
  String get voiceCharUpbeat => 'upbeat';

  @override
  String get voiceCharYouthful => 'youthful';

  @override
  String get voiceCharForward => 'forward';

  @override
  String get voiceCharWarm => 'warm';

  @override
  String get voiceCharGentle => 'gentle';

  @override
  String get voiceCharFriendly => 'friendly';

  @override
  String get voiceCharGravelly => 'gravelly';

  @override
  String get voiceCharInformative => 'informative';

  @override
  String get voiceCharBreathy => 'breathy';

  @override
  String get voiceCharExcitable => 'excitable';

  @override
  String get voiceCharLively => 'lively';

  @override
  String get voiceCharKnowledgeable => 'knowledgeable';

  @override
  String get voiceCharEven => 'even';

  @override
  String get voiceCharEasygoing => 'easy-going';

  @override
  String get voiceCharConversational => 'conversational';
}
