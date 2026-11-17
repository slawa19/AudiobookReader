// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get mediaChannel => 'Прослуховування книг';

  @override
  String get mediaPrevious => 'Попередній фрагмент';

  @override
  String get mediaNext => 'Наступний фрагмент';

  @override
  String get shelfTitle => 'Книги';

  @override
  String get settings => 'Налаштування';

  @override
  String get fakeVoice => 'Тестовий голос';

  @override
  String get addBook => 'Додати книгу';

  @override
  String get continueReading => 'Продовжити';

  @override
  String get progressNew => 'нова';

  @override
  String get adding => 'Додається…';

  @override
  String get dismiss => 'Прибрати';

  @override
  String get emptyTitle => 'Полиця порожня';

  @override
  String get emptyBody =>
      'Додайте книгу у форматі FB2 або EPUB кнопкою «+» або відкрийте файл з іншого застосунку через «Відкрити за допомогою».';

  @override
  String get addFailedUnsupported => 'Цей формат не підтримується';

  @override
  String get addFailedUnreadable => 'Не вдалося прочитати книгу';

  @override
  String get addFailedProtected =>
      'Книга захищена від копіювання, відкрити її не можна';

  @override
  String get deleteNarration => 'Видалити озвучення';

  @override
  String get deleteBook => 'Видалити книгу';

  @override
  String get deleteBookTitle => 'Видалити книгу?';

  @override
  String deleteBookBody(String title, String size) {
    return '«$title» і її озвучення буде видалено з телефона. Звільниться $size.';
  }

  @override
  String get deleteNarrationTitle => 'Видалити озвучення книги?';

  @override
  String deleteNarrationBody(String title, String size) {
    return 'Звук «$title» буде видалено, звільниться $size. Щоб послухати знову, його доведеться озвучити й оплатити заново.';
  }

  @override
  String get cancel => 'Скасувати';

  @override
  String get delete => 'Видалити';

  @override
  String get pickerTitle => 'Вибір файлу';

  @override
  String get pickerNote =>
      'У прототипі — імітація системного вікна вибору файлу.';

  @override
  String get back => 'Назад';

  @override
  String get contents => 'Зміст';

  @override
  String get textAppearance => 'Вигляд тексту';

  @override
  String get listen => 'Слухати';

  @override
  String get readFromHere => 'Читати звідси';

  @override
  String get toReadingPlace => 'До місця читання';

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

    return '$valueString книги';
  }

  @override
  String note(String number) {
    return 'Примітка $number';
  }

  @override
  String get size => 'Розмір';

  @override
  String get smaller => 'Дрібніше';

  @override
  String get larger => 'Крупніше';

  @override
  String get theme => 'Тема';

  @override
  String get asSystem => 'Як у системі';

  @override
  String get themeLight => 'Світла';

  @override
  String get themeSepia => 'Сепія';

  @override
  String get themeDark => 'Темна';

  @override
  String get preparing => 'Готую голос…';

  @override
  String get waiting => 'Чекаю на зв’язок…';

  @override
  String get close => 'Закрити';

  @override
  String get pause => 'Пауза';

  @override
  String get previous => 'Попередній абзац';

  @override
  String get next => 'Наступний абзац';

  @override
  String get speed => 'Швидкість';

  @override
  String get sleepTimer => 'Таймер сну';

  @override
  String get voice => 'Голос';

  @override
  String minutesShort(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString хв';
  }

  @override
  String get endOfChapterShort => 'розділ';

  @override
  String speedValue(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString×';
  }

  @override
  String get endOfBook => 'Книга закінчилась';

  @override
  String get endOfBookBody => 'Щоб читати очима, закрийте панель.';

  @override
  String get error402Title => 'На рахунку Gemini закінчилися кошти';

  @override
  String get error402Body =>
      'Поповніть рахунок і натисніть «Слухати» — продовжимо з цього абзацу.';

  @override
  String error404Title(String model) {
    return 'Модель $model більше недоступна';
  }

  @override
  String get error404Body => 'Виберіть іншу модель.';

  @override
  String get errorKeyTitle => 'Google не прийняв ключ Gemini';

  @override
  String get errorKeyBody =>
      'Перевірте ключ у налаштуваннях і натисніть «Слухати».';

  @override
  String get changeKey => 'Змінити ключ';

  @override
  String get errorOtherTitle => 'Google відмовив в озвученні';

  @override
  String google(String message) {
    return 'Google: «$message»';
  }

  @override
  String quoted(String message) {
    return '«$message»';
  }

  @override
  String get topUp => 'Поповнити';

  @override
  String get chooseModel => 'Вибрати модель';

  @override
  String linkStub(String url) {
    return 'У прототипі посилання не відкриваються: $url';
  }

  @override
  String sleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хвилини',
      many: '$count хвилин',
      few: '$count хвилини',
      one: '$count хвилина',
    );
    return '$_temp0';
  }

  @override
  String get sleepEndOfChapter => 'До кінця розділу';

  @override
  String get sleepOff => 'Вимкнути';

  @override
  String sleepActive(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Пауза через $countString хв';
  }

  @override
  String get sleepActiveChapter => 'Пауза в кінці розділу';

  @override
  String get voiced => 'озвучена';

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

    return 'Не озвучено: ≈ $minutesString хв звуку, ≈ $priceString';
  }

  @override
  String get downloadChapter => 'Завантажити розділ';

  @override
  String get downloadAgain => 'Завантажити знову';

  @override
  String downloading(int ready, int total) {
    final intl.NumberFormat readyNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String readyString = readyNumberFormat.format(ready);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Озвучую: готово $readyString із $totalString хв';
  }

  @override
  String get downloadingWhileOpen => 'Триває, поки застосунок відкритий.';

  @override
  String get stopDownload => 'Зупинити';

  @override
  String downloadStrip(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return 'Завантажую розділ · $valueString';
  }

  @override
  String get stopShort => 'Стоп';

  @override
  String get downloadFailed => 'Завантаження зупинилося';

  @override
  String voiceForBook(String title) {
    return 'для книги «$title»';
  }

  @override
  String get voiceForApp => 'для всіх книг';

  @override
  String get voiceAsSettings => 'Як у налаштуваннях';

  @override
  String voiceNow(String name) {
    return 'зараз $name';
  }

  @override
  String female(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Жіночі · $countString';
  }

  @override
  String male(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Чоловічі · $countString';
  }

  @override
  String get probe => 'Проба';

  @override
  String probeNote(String phrase) {
    return 'Проба читає одну й ту саму фразу мовою книги: «$phrase» Коштує менше за цент і оплачується один раз.';
  }

  @override
  String get probeFailed => 'Проба не вдалася';

  @override
  String get geminiKey => 'Ключ Gemini';

  @override
  String get change => 'Змінити';

  @override
  String get whereKey => 'Де взяти ключ: aistudio.google.com';

  @override
  String get needKey =>
      'Щоб слухати, потрібен ключ Gemini. Його вводять один раз, і він зберігається лише на телефоні.';

  @override
  String get pasteKey => 'Вставте ключ';

  @override
  String get paste => 'Вставити';

  @override
  String get model => 'Модель';

  @override
  String perHour(double price) {
    final intl.NumberFormat priceNumberFormat = intl.NumberFormat.currency(
      locale: localeName,
      symbol: '\$',
      decimalDigits: 2,
    );
    final String priceString = priceNumberFormat.format(price);

    return '$priceString за годину звуку';
  }

  @override
  String get byDefault => 'за замовчуванням';

  @override
  String get thirdCheaper => 'на третину дешевше';

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

    return 'З 1 січня 2027 року Google братиме вдвічі більше: $aString і $bString за годину. Звук однієї моделі не зараховується іншій: після зміни книги озвучуються заново.';
  }

  @override
  String get spent => 'Витрачено';

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
  String get storage => 'Озвучення на телефоні';

  @override
  String get clear => 'Очистити';

  @override
  String get storageNote =>
      'Озвучене вдруге не оплачується. Після очищення його доведеться озвучити й оплатити заново.';

  @override
  String get clearTitle => 'Очистити озвучення?';

  @override
  String clearBody(String size) {
    return 'Буде видалено $size звуку всіх книг і проб голосу. Щоб послухати знову, його доведеться озвучити й оплатити заново.';
  }

  @override
  String megabytes(int size) {
    final intl.NumberFormat sizeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString МБ';
  }

  @override
  String gigabytes(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString ГБ';
  }

  @override
  String get language => 'Мова';

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
  String get voiceCharSoft => 'м’який';

  @override
  String get voiceCharBreezy => 'легкий, безтурботний';

  @override
  String get voiceCharBright => 'яскравий';

  @override
  String get voiceCharCalm => 'спокійний';

  @override
  String get voiceCharSmooth => 'плавний';

  @override
  String get voiceCharClear => 'чіткий';

  @override
  String get voiceCharMature => 'зрілий';

  @override
  String get voiceCharFirm => 'твердий';

  @override
  String get voiceCharUpbeat => 'бадьорий';

  @override
  String get voiceCharYouthful => 'молодий';

  @override
  String get voiceCharForward => 'наполегливий';

  @override
  String get voiceCharWarm => 'теплий';

  @override
  String get voiceCharGentle => 'ніжний';

  @override
  String get voiceCharFriendly => 'дружелюбний';

  @override
  String get voiceCharGravelly => 'із хрипотою';

  @override
  String get voiceCharInformative => 'діловий';

  @override
  String get voiceCharBreathy => 'з придихом';

  @override
  String get voiceCharExcitable => 'збуджений';

  @override
  String get voiceCharLively => 'жвавий';

  @override
  String get voiceCharKnowledgeable => 'обізнаний';

  @override
  String get voiceCharEven => 'рівний';

  @override
  String get voiceCharEasygoing => 'невимушений';

  @override
  String get voiceCharConversational => 'розмовний';
}
