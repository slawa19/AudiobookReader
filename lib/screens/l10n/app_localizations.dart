import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('pl'),
    Locale('de'),
  ];

  /// No description provided for @mediaChannel.
  ///
  /// In ru, this message translates to:
  /// **'Прослушивание книг'**
  String get mediaChannel;

  /// No description provided for @mediaPrevious.
  ///
  /// In ru, this message translates to:
  /// **'Предыдущий отрезок'**
  String get mediaPrevious;

  /// No description provided for @mediaNext.
  ///
  /// In ru, this message translates to:
  /// **'Следующий отрезок'**
  String get mediaNext;

  /// Заголовок полки
  ///
  /// In ru, this message translates to:
  /// **'Книги'**
  String get shelfTitle;

  /// No description provided for @settings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settings;

  /// No description provided for @fakeVoice.
  ///
  /// In ru, this message translates to:
  /// **'Подставной голос'**
  String get fakeVoice;

  /// No description provided for @addBook.
  ///
  /// In ru, this message translates to:
  /// **'Добавить книгу'**
  String get addBook;

  /// No description provided for @continueReading.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueReading;

  /// Книгу ещё не открывали
  ///
  /// In ru, this message translates to:
  /// **'новая'**
  String get progressNew;

  /// No description provided for @adding.
  ///
  /// In ru, this message translates to:
  /// **'Добавляется…'**
  String get adding;

  /// No description provided for @dismiss.
  ///
  /// In ru, this message translates to:
  /// **'Убрать'**
  String get dismiss;

  /// No description provided for @emptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Полка пуста'**
  String get emptyTitle;

  /// No description provided for @emptyBody.
  ///
  /// In ru, this message translates to:
  /// **'Добавьте книгу в FB2 или EPUB кнопкой «+» или откройте файл из другого приложения через «Открыть с помощью».'**
  String get emptyBody;

  /// No description provided for @addFailedUnsupported.
  ///
  /// In ru, this message translates to:
  /// **'Этот формат не поддерживается'**
  String get addFailedUnsupported;

  /// No description provided for @addFailedUnreadable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось прочитать книгу'**
  String get addFailedUnreadable;

  /// No description provided for @addFailedProtected.
  ///
  /// In ru, this message translates to:
  /// **'Книга защищена от копирования, открыть её нельзя'**
  String get addFailedProtected;

  /// No description provided for @deleteNarration.
  ///
  /// In ru, this message translates to:
  /// **'Удалить озвучку'**
  String get deleteNarration;

  /// No description provided for @deleteBook.
  ///
  /// In ru, this message translates to:
  /// **'Удалить книгу'**
  String get deleteBook;

  /// No description provided for @deleteBookTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить книгу?'**
  String get deleteBookTitle;

  /// No description provided for @deleteBookBody.
  ///
  /// In ru, this message translates to:
  /// **'«{title}» и её озвучка удалятся с телефона. Освободится {size}.'**
  String deleteBookBody(String title, String size);

  /// No description provided for @deleteNarrationTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить озвучку книги?'**
  String get deleteNarrationTitle;

  /// No description provided for @deleteNarrationBody.
  ///
  /// In ru, this message translates to:
  /// **'Звук «{title}» удалится, освободится {size}. Чтобы послушать снова, его придётся озвучить и оплатить заново.'**
  String deleteNarrationBody(String title, String size);

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get delete;

  /// No description provided for @pickerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выбор файла'**
  String get pickerTitle;

  /// No description provided for @pickerNote.
  ///
  /// In ru, this message translates to:
  /// **'В прототипе — имитация системного окна выбора файла.'**
  String get pickerNote;

  /// No description provided for @back.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get back;

  /// No description provided for @contents.
  ///
  /// In ru, this message translates to:
  /// **'Оглавление'**
  String get contents;

  /// No description provided for @textAppearance.
  ///
  /// In ru, this message translates to:
  /// **'Вид текста'**
  String get textAppearance;

  /// No description provided for @listen.
  ///
  /// In ru, this message translates to:
  /// **'Слушать'**
  String get listen;

  /// No description provided for @readFromHere.
  ///
  /// In ru, this message translates to:
  /// **'Читать отсюда'**
  String get readFromHere;

  /// No description provided for @toReadingPlace.
  ///
  /// In ru, this message translates to:
  /// **'К месту чтения'**
  String get toReadingPlace;

  /// Доля книги, формат по локали
  ///
  /// In ru, this message translates to:
  /// **'{value}'**
  String percent(double value);

  /// No description provided for @ofBook.
  ///
  /// In ru, this message translates to:
  /// **'{value} книги'**
  String ofBook(double value);

  /// No description provided for @note.
  ///
  /// In ru, this message translates to:
  /// **'Примечание {number}'**
  String note(String number);

  /// No description provided for @size.
  ///
  /// In ru, this message translates to:
  /// **'Размер'**
  String get size;

  /// No description provided for @smaller.
  ///
  /// In ru, this message translates to:
  /// **'Мельче'**
  String get smaller;

  /// No description provided for @larger.
  ///
  /// In ru, this message translates to:
  /// **'Крупнее'**
  String get larger;

  /// No description provided for @theme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get theme;

  /// No description provided for @asSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get asSystem;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeSepia.
  ///
  /// In ru, this message translates to:
  /// **'Сепия'**
  String get themeSepia;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @preparing.
  ///
  /// In ru, this message translates to:
  /// **'Готовлю голос…'**
  String get preparing;

  /// No description provided for @waiting.
  ///
  /// In ru, this message translates to:
  /// **'Жду связь…'**
  String get waiting;

  /// No description provided for @close.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;

  /// No description provided for @pause.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get pause;

  /// No description provided for @previous.
  ///
  /// In ru, this message translates to:
  /// **'Предыдущий абзац'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In ru, this message translates to:
  /// **'Следующий абзац'**
  String get next;

  /// No description provided for @speed.
  ///
  /// In ru, this message translates to:
  /// **'Скорость'**
  String get speed;

  /// No description provided for @sleepTimer.
  ///
  /// In ru, this message translates to:
  /// **'Таймер сна'**
  String get sleepTimer;

  /// No description provided for @voice.
  ///
  /// In ru, this message translates to:
  /// **'Голос'**
  String get voice;

  /// Сокращение «минут» — без склонения
  ///
  /// In ru, this message translates to:
  /// **'{count} мин'**
  String minutesShort(int count);

  /// No description provided for @endOfChapterShort.
  ///
  /// In ru, this message translates to:
  /// **'глава'**
  String get endOfChapterShort;

  /// No description provided for @speedValue.
  ///
  /// In ru, this message translates to:
  /// **'{value}×'**
  String speedValue(double value);

  /// No description provided for @endOfBook.
  ///
  /// In ru, this message translates to:
  /// **'Книга закончилась'**
  String get endOfBook;

  /// No description provided for @endOfBookBody.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы читать глазами, закройте панель.'**
  String get endOfBookBody;

  /// No description provided for @error402Title.
  ///
  /// In ru, this message translates to:
  /// **'На счёте Gemini закончились деньги'**
  String get error402Title;

  /// Автопродолжения нет (FR-P6): только «нажмите Слушать»
  ///
  /// In ru, this message translates to:
  /// **'Пополните счёт и нажмите «Слушать» — продолжим с этого абзаца.'**
  String get error402Body;

  /// No description provided for @error404Title.
  ///
  /// In ru, this message translates to:
  /// **'Модель {model} больше недоступна'**
  String error404Title(String model);

  /// No description provided for @error404Body.
  ///
  /// In ru, this message translates to:
  /// **'Выберите другую модель.'**
  String get error404Body;

  /// No description provided for @errorKeyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Google не принял ключ Gemini'**
  String get errorKeyTitle;

  /// No description provided for @errorKeyBody.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте ключ в настройках и нажмите «Слушать».'**
  String get errorKeyBody;

  /// No description provided for @changeKey.
  ///
  /// In ru, this message translates to:
  /// **'Изменить ключ'**
  String get changeKey;

  /// No description provided for @errorOtherTitle.
  ///
  /// In ru, this message translates to:
  /// **'Google отказал в озвучке'**
  String get errorOtherTitle;

  /// Текст Google — как есть, без перевода
  ///
  /// In ru, this message translates to:
  /// **'Google: «{message}»'**
  String google(String message);

  /// No description provided for @quoted.
  ///
  /// In ru, this message translates to:
  /// **'«{message}»'**
  String quoted(String message);

  /// No description provided for @topUp.
  ///
  /// In ru, this message translates to:
  /// **'Пополнить'**
  String get topUp;

  /// No description provided for @chooseModel.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать модель'**
  String get chooseModel;

  /// No description provided for @linkStub.
  ///
  /// In ru, this message translates to:
  /// **'В прототипе ссылки не открываются: {url}'**
  String linkStub(String url);

  /// No description provided for @sleepMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} минута} few{{count} минуты} many{{count} минут} other{{count} минуты}}'**
  String sleepMinutes(int count);

  /// No description provided for @sleepEndOfChapter.
  ///
  /// In ru, this message translates to:
  /// **'До конца главы'**
  String get sleepEndOfChapter;

  /// No description provided for @sleepOff.
  ///
  /// In ru, this message translates to:
  /// **'Выключить'**
  String get sleepOff;

  /// No description provided for @sleepActive.
  ///
  /// In ru, this message translates to:
  /// **'Пауза через {count} мин'**
  String sleepActive(int count);

  /// No description provided for @sleepActiveChapter.
  ///
  /// In ru, this message translates to:
  /// **'Пауза в конце главы'**
  String get sleepActiveChapter;

  /// Глава полностью озвучена
  ///
  /// In ru, this message translates to:
  /// **'озвучена'**
  String get voiced;

  /// Оценка перед «Скачать главу» (FR-D2)
  ///
  /// In ru, this message translates to:
  /// **'Не озвучено: ≈ {minutes} мин звука, ≈ {price}'**
  String notVoicedEstimate(int minutes, double price);

  /// No description provided for @downloadChapter.
  ///
  /// In ru, this message translates to:
  /// **'Скачать главу'**
  String get downloadChapter;

  /// No description provided for @downloadAgain.
  ///
  /// In ru, this message translates to:
  /// **'Скачать снова'**
  String get downloadAgain;

  /// No description provided for @downloading.
  ///
  /// In ru, this message translates to:
  /// **'Озвучиваю: готово {ready} из {total} мин'**
  String downloading(int ready, int total);

  /// No description provided for @downloadingWhileOpen.
  ///
  /// In ru, this message translates to:
  /// **'Идёт, пока приложение открыто.'**
  String get downloadingWhileOpen;

  /// No description provided for @stopDownload.
  ///
  /// In ru, this message translates to:
  /// **'Остановить'**
  String get stopDownload;

  /// No description provided for @downloadStrip.
  ///
  /// In ru, this message translates to:
  /// **'Скачиваю главу · {value}'**
  String downloadStrip(double value);

  /// No description provided for @stopShort.
  ///
  /// In ru, this message translates to:
  /// **'Стоп'**
  String get stopShort;

  /// No description provided for @downloadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Скачивание остановилось'**
  String get downloadFailed;

  /// No description provided for @voiceForBook.
  ///
  /// In ru, this message translates to:
  /// **'для книги «{title}»'**
  String voiceForBook(String title);

  /// No description provided for @voiceForApp.
  ///
  /// In ru, this message translates to:
  /// **'для всех книг'**
  String get voiceForApp;

  /// No description provided for @voiceAsSettings.
  ///
  /// In ru, this message translates to:
  /// **'Как в настройках'**
  String get voiceAsSettings;

  /// No description provided for @voiceNow.
  ///
  /// In ru, this message translates to:
  /// **'сейчас {name}'**
  String voiceNow(String name);

  /// No description provided for @female.
  ///
  /// In ru, this message translates to:
  /// **'Женские · {count}'**
  String female(int count);

  /// No description provided for @male.
  ///
  /// In ru, this message translates to:
  /// **'Мужские · {count}'**
  String male(int count);

  /// No description provided for @probe.
  ///
  /// In ru, this message translates to:
  /// **'Проба'**
  String get probe;

  /// No description provided for @probeNote.
  ///
  /// In ru, this message translates to:
  /// **'Проба читает одну и ту же фразу на языке книги: «{phrase}» Стоит меньше цента и оплачивается один раз.'**
  String probeNote(String phrase);

  /// No description provided for @probeFailed.
  ///
  /// In ru, this message translates to:
  /// **'Проба не удалась'**
  String get probeFailed;

  /// No description provided for @geminiKey.
  ///
  /// In ru, this message translates to:
  /// **'Ключ Gemini'**
  String get geminiKey;

  /// No description provided for @change.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get change;

  /// No description provided for @whereKey.
  ///
  /// In ru, this message translates to:
  /// **'Где взять ключ: aistudio.google.com'**
  String get whereKey;

  /// No description provided for @needKey.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы слушать, нужен ключ Gemini. Он вводится один раз и хранится только на телефоне.'**
  String get needKey;

  /// No description provided for @pasteKey.
  ///
  /// In ru, this message translates to:
  /// **'Вставьте ключ'**
  String get pasteKey;

  /// No description provided for @paste.
  ///
  /// In ru, this message translates to:
  /// **'Вставить'**
  String get paste;

  /// No description provided for @model.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get model;

  /// No description provided for @perHour.
  ///
  /// In ru, this message translates to:
  /// **'{price} за час звука'**
  String perHour(double price);

  /// No description provided for @byDefault.
  ///
  /// In ru, this message translates to:
  /// **'по умолчанию'**
  String get byDefault;

  /// No description provided for @thirdCheaper.
  ///
  /// In ru, this message translates to:
  /// **'на треть дешевле'**
  String get thirdCheaper;

  /// No description provided for @price2027.
  ///
  /// In ru, this message translates to:
  /// **'С 1 января 2027 года Google берёт вдвое больше: {a} и {b} за час. Звук одной модели другой не засчитывается: после смены книги озвучиваются заново.'**
  String price2027(double a, double b);

  /// No description provided for @spent.
  ///
  /// In ru, this message translates to:
  /// **'Потрачено'**
  String get spent;

  /// Сумма в долларах, формат по локали
  ///
  /// In ru, this message translates to:
  /// **'{amount}'**
  String money(double amount);

  /// No description provided for @storage.
  ///
  /// In ru, this message translates to:
  /// **'Озвучка на телефоне'**
  String get storage;

  /// No description provided for @clear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get clear;

  /// No description provided for @storageNote.
  ///
  /// In ru, this message translates to:
  /// **'Озвученное второй раз не оплачивается. После очистки его придётся озвучить и оплатить заново.'**
  String get storageNote;

  /// No description provided for @clearTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить озвучку?'**
  String get clearTitle;

  /// No description provided for @clearBody.
  ///
  /// In ru, this message translates to:
  /// **'Удалится {size} звука всех книг и проб голоса. Чтобы послушать снова, его придётся озвучить и оплатить заново.'**
  String clearBody(String size);

  /// No description provided for @megabytes.
  ///
  /// In ru, this message translates to:
  /// **'{size} МБ'**
  String megabytes(int size);

  /// No description provided for @gigabytes.
  ///
  /// In ru, this message translates to:
  /// **'{size} ГБ'**
  String gigabytes(double size);

  /// No description provided for @language.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get language;

  /// No description provided for @langRu.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get langRu;

  /// No description provided for @langEn.
  ///
  /// In ru, this message translates to:
  /// **'English'**
  String get langEn;

  /// No description provided for @langPl.
  ///
  /// In ru, this message translates to:
  /// **'Polski'**
  String get langPl;

  /// No description provided for @langDe.
  ///
  /// In ru, this message translates to:
  /// **'Deutsch'**
  String get langDe;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'мягкий'**
  String get voiceCharSoft;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'лёгкий, непринуждённый'**
  String get voiceCharBreezy;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'яркий'**
  String get voiceCharBright;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'спокойный'**
  String get voiceCharCalm;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'плавный'**
  String get voiceCharSmooth;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'чёткий'**
  String get voiceCharClear;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'зрелый'**
  String get voiceCharMature;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'твёрдый'**
  String get voiceCharFirm;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'бодрый'**
  String get voiceCharUpbeat;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'молодой'**
  String get voiceCharYouthful;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'напористый'**
  String get voiceCharForward;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'тёплый'**
  String get voiceCharWarm;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'нежный'**
  String get voiceCharGentle;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'дружелюбный'**
  String get voiceCharFriendly;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'с хрипотцой'**
  String get voiceCharGravelly;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'деловой'**
  String get voiceCharInformative;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'с придыханием'**
  String get voiceCharBreathy;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'возбуждённый'**
  String get voiceCharExcitable;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'живой'**
  String get voiceCharLively;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'знающий'**
  String get voiceCharKnowledgeable;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'ровный'**
  String get voiceCharEven;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'непринуждённый'**
  String get voiceCharEasygoing;

  /// Характер голоса
  ///
  /// In ru, this message translates to:
  /// **'разговорный'**
  String get voiceCharConversational;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'pl', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
