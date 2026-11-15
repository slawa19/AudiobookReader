// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get mediaChannel => 'Прослушивание книг';

  @override
  String get mediaPrevious => 'Предыдущий отрезок';

  @override
  String get mediaNext => 'Следующий отрезок';

  @override
  String get shelfTitle => 'Книги';

  @override
  String get settings => 'Настройки';

  @override
  String get fakeVoice => 'Подставной голос';

  @override
  String get addBook => 'Добавить книгу';

  @override
  String get continueReading => 'Продолжить';

  @override
  String get progressNew => 'новая';

  @override
  String get adding => 'Добавляется…';

  @override
  String get dismiss => 'Убрать';

  @override
  String get emptyTitle => 'Полка пуста';

  @override
  String get emptyBody =>
      'Добавьте книгу в FB2 или EPUB кнопкой «+» или откройте файл из другого приложения через «Открыть с помощью».';

  @override
  String get addFailedUnsupported => 'Этот формат не поддерживается';

  @override
  String get addFailedUnreadable => 'Не удалось прочитать книгу';

  @override
  String get addFailedProtected =>
      'Книга защищена от копирования, открыть её нельзя';

  @override
  String get deleteNarration => 'Удалить озвучку';

  @override
  String get deleteBook => 'Удалить книгу';

  @override
  String get deleteBookTitle => 'Удалить книгу?';

  @override
  String deleteBookBody(String title, String size) {
    return '«$title» и её озвучка удалятся с телефона. Освободится $size.';
  }

  @override
  String get deleteNarrationTitle => 'Удалить озвучку книги?';

  @override
  String deleteNarrationBody(String title, String size) {
    return 'Звук «$title» удалится, освободится $size. Чтобы послушать снова, его придётся озвучить и оплатить заново.';
  }

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get pickerTitle => 'Выбор файла';

  @override
  String get pickerNote =>
      'В прототипе — имитация системного окна выбора файла.';

  @override
  String get back => 'Назад';

  @override
  String get contents => 'Оглавление';

  @override
  String get textAppearance => 'Вид текста';

  @override
  String get listen => 'Слушать';

  @override
  String get readFromHere => 'Читать отсюда';

  @override
  String get toReadingPlace => 'К месту чтения';

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
    return 'Примечание $number';
  }

  @override
  String get size => 'Размер';

  @override
  String get smaller => 'Мельче';

  @override
  String get larger => 'Крупнее';

  @override
  String get theme => 'Тема';

  @override
  String get asSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeSepia => 'Сепия';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get preparing => 'Готовлю голос…';

  @override
  String get waiting => 'Жду связь…';

  @override
  String get close => 'Закрыть';

  @override
  String get pause => 'Пауза';

  @override
  String get previous => 'Предыдущий абзац';

  @override
  String get next => 'Следующий абзац';

  @override
  String get speed => 'Скорость';

  @override
  String get sleepTimer => 'Таймер сна';

  @override
  String get voice => 'Голос';

  @override
  String minutesShort(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString мин';
  }

  @override
  String get endOfChapterShort => 'глава';

  @override
  String speedValue(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString×';
  }

  @override
  String get endOfBook => 'Книга закончилась';

  @override
  String get endOfBookBody => 'Чтобы читать глазами, закройте панель.';

  @override
  String get error402Title => 'На счёте Gemini закончились деньги';

  @override
  String get error402Body =>
      'Пополните счёт и нажмите «Слушать» — продолжим с этого абзаца.';

  @override
  String error404Title(String model) {
    return 'Модель $model больше недоступна';
  }

  @override
  String get error404Body => 'Выберите другую модель.';

  @override
  String get errorKeyTitle => 'Google не принял ключ Gemini';

  @override
  String get errorKeyBody => 'Проверьте ключ в настройках и нажмите «Слушать».';

  @override
  String get changeKey => 'Изменить ключ';

  @override
  String get errorOtherTitle => 'Google отказал в озвучке';

  @override
  String google(String message) {
    return 'Google: «$message»';
  }

  @override
  String quoted(String message) {
    return '«$message»';
  }

  @override
  String get topUp => 'Пополнить';

  @override
  String get chooseModel => 'Выбрать модель';

  @override
  String linkStub(String url) {
    return 'В прототипе ссылки не открываются: $url';
  }

  @override
  String sleepMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count минуты',
      many: '$count минут',
      few: '$count минуты',
      one: '$count минута',
    );
    return '$_temp0';
  }

  @override
  String get sleepEndOfChapter => 'До конца главы';

  @override
  String get sleepOff => 'Выключить';

  @override
  String sleepActive(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Пауза через $countString мин';
  }

  @override
  String get sleepActiveChapter => 'Пауза в конце главы';

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

    return 'Не озвучено: ≈ $minutesString мин звука, ≈ $priceString';
  }

  @override
  String get downloadChapter => 'Скачать главу';

  @override
  String get downloadAgain => 'Скачать снова';

  @override
  String downloading(int ready, int total) {
    final intl.NumberFormat readyNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String readyString = readyNumberFormat.format(ready);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Озвучиваю: готово $readyString из $totalString мин';
  }

  @override
  String get downloadingWhileOpen => 'Идёт, пока приложение открыто.';

  @override
  String get stopDownload => 'Остановить';

  @override
  String downloadStrip(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return 'Скачиваю главу · $valueString';
  }

  @override
  String get stopShort => 'Стоп';

  @override
  String get downloadFailed => 'Скачивание остановилось';

  @override
  String voiceForBook(String title) {
    return 'для книги «$title»';
  }

  @override
  String get voiceForApp => 'для всех книг';

  @override
  String get voiceAsSettings => 'Как в настройках';

  @override
  String voiceNow(String name) {
    return 'сейчас $name';
  }

  @override
  String female(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Женские · $countString';
  }

  @override
  String male(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Мужские · $countString';
  }

  @override
  String get probe => 'Проба';

  @override
  String probeNote(String phrase) {
    return 'Проба читает одну и ту же фразу на языке книги: «$phrase» Стоит меньше цента и оплачивается один раз.';
  }

  @override
  String get probeFailed => 'Проба не удалась';

  @override
  String get geminiKey => 'Ключ Gemini';

  @override
  String get change => 'Изменить';

  @override
  String get whereKey => 'Где взять ключ: aistudio.google.com';

  @override
  String get needKey =>
      'Чтобы слушать, нужен ключ Gemini. Он вводится один раз и хранится только на телефоне.';

  @override
  String get pasteKey => 'Вставьте ключ';

  @override
  String get paste => 'Вставить';

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

    return '$priceString за час звука';
  }

  @override
  String get byDefault => 'по умолчанию';

  @override
  String get thirdCheaper => 'на треть дешевле';

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

    return 'С 1 января 2027 года Google берёт вдвое больше: $aString и $bString за час. Звук одной модели другой не засчитывается: после смены книги озвучиваются заново.';
  }

  @override
  String get spent => 'Потрачено';

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
  String get storage => 'Озвучка на телефоне';

  @override
  String get clear => 'Очистить';

  @override
  String get storageNote =>
      'Озвученное второй раз не оплачивается. После очистки его придётся озвучить и оплатить заново.';

  @override
  String get clearTitle => 'Очистить озвучку?';

  @override
  String clearBody(String size) {
    return 'Удалится $size звука всех книг и проб голоса. Чтобы послушать снова, его придётся озвучить и оплатить заново.';
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
  String get language => 'Язык';

  @override
  String get langRu => 'Русский';

  @override
  String get langEn => 'English';

  @override
  String get langPl => 'Polski';

  @override
  String get langDe => 'Deutsch';

  @override
  String get voiceCharSoft => 'мягкий';

  @override
  String get voiceCharBreezy => 'лёгкий, непринуждённый';

  @override
  String get voiceCharBright => 'яркий';

  @override
  String get voiceCharCalm => 'спокойный';

  @override
  String get voiceCharSmooth => 'плавный';

  @override
  String get voiceCharClear => 'чёткий';

  @override
  String get voiceCharMature => 'зрелый';

  @override
  String get voiceCharFirm => 'твёрдый';

  @override
  String get voiceCharUpbeat => 'бодрый';

  @override
  String get voiceCharYouthful => 'молодой';

  @override
  String get voiceCharForward => 'напористый';

  @override
  String get voiceCharWarm => 'тёплый';

  @override
  String get voiceCharGentle => 'нежный';

  @override
  String get voiceCharFriendly => 'дружелюбный';

  @override
  String get voiceCharGravelly => 'с хрипотцой';

  @override
  String get voiceCharInformative => 'деловой';

  @override
  String get voiceCharBreathy => 'с придыханием';

  @override
  String get voiceCharExcitable => 'возбуждённый';

  @override
  String get voiceCharLively => 'живой';

  @override
  String get voiceCharKnowledgeable => 'знающий';

  @override
  String get voiceCharEven => 'ровный';

  @override
  String get voiceCharEasygoing => 'непринуждённый';

  @override
  String get voiceCharConversational => 'разговорный';
}
