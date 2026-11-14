// Все строки интерфейса — здесь, а не в коде экранов (AGENTS.md, «Интерфейс»).
//
// Файл лежит в `screens`, а не в `app`, хотя А§2 относит строки к `app`: `screens` не вправе импортировать
// `app`, а строки нужны именно экранам. Противоречие записано в docs/prototype/README.md.

const _nb = ' ';

abstract final class S {
  // Полка
  static const shelfTitle = 'Книги';
  static const settings = 'Настройки';
  static const addBook = 'Добавить книгу';
  static const continueReading = 'Продолжить';
  static const progressNew = 'новая';
  static const adding = 'Добавляется…';
  static const dismiss = 'Убрать';
  static const emptyTitle = 'Полка пуста';
  static const emptyBody = 'Добавьте книгу в FB2 или EPUB кнопкой «+» или откройте файл из другого приложения '
      'через «Открыть с помощью».';
  static const deleteNarration = 'Удалить озвучку';
  static const deleteBook = 'Удалить книгу';
  static const deleteBookTitle = 'Удалить книгу?';
  static String deleteBookBody(String title, String size) =>
      '«$title» и её озвучка удалятся с телефона. Освободится $size.';
  static const deleteNarrationTitle = 'Удалить озвучку книги?';
  static String deleteNarrationBody(String title, String size) =>
      'Звук «$title» удалится, освободится $size. Чтобы послушать снова, его придётся озвучить и оплатить заново.';
  static const cancel = 'Отмена';
  static const delete = 'Удалить';
  static const pickerTitle = 'Выбор файла';
  static const pickerNote = 'В прототипе — имитация системного окна выбора файла.';

  // Чтение
  static const back = 'Назад';
  static const contents = 'Оглавление';
  static const textAppearance = 'Вид текста';
  static const listen = 'Слушать';
  static const readFromHere = 'Читать отсюда';
  static const toReadingPlace = 'К месту чтения';
  static String bookPercent(int p) => '$p$_nb%';
  static String ofBook(int p) => '$p$_nb% книги';
  static String note(String n) => 'Примечание $n';

  // Вид текста
  static const size = 'Размер';
  static const theme = 'Тема';
  static const themeSystem = 'Как в системе';
  static const themeLight = 'Светлая';
  static const themeSepia = 'Сепия';
  static const themeDark = 'Тёмная';

  // Плеер
  static const preparing = 'Готовлю голос…';
  static const waiting = 'Жду связь…';
  static const close = 'Закрыть';
  static const play = 'Слушать';
  static const pause = 'Пауза';
  static const previous = 'Предыдущий абзац';
  static const next = 'Следующий абзац';
  static const speed = 'Скорость';
  static const sleepTimer = 'Таймер сна';
  static const voice = 'Голос';
  static String minutesLeft(int m) => '$m$_nbмин';
  static const endOfChapterShort = 'глава';
  static String speedLabel(double s) => '${_num(s)}×';
  static const endOfBook = 'Книга закончилась';
  static const endOfBookBody = 'Чтобы читать глазами, закройте панель.';
  static const error402Title = 'На счёте Gemini закончились деньги';
  static const error402Body = 'После пополнения чтение продолжится с этого абзаца.';
  static String error404Title(String model) => 'Модель $model больше недоступна';
  static const error404Body = 'Выберите другую модель.';
  static const errorOtherTitle = 'Google отказал в озвучке';
  static String google(String message) => 'Google: «$message»';
  static const topUp = 'Пополнить';
  static const chooseModel = 'Выбрать модель';
  static const billingUrl = 'https://aistudio.google.com/billing';
  static const keyUrl = 'https://aistudio.google.com/apikey';
  static String linkStub(String url) => 'В прототипе ссылки не открываются: $url';

  // Таймер сна
  static String sleepMinutes(int m) => '$m$_nbминут';
  static const sleepEndOfChapter = 'До конца главы';
  static const sleepOff = 'Выключить';
  static String sleepActive(int m) => 'Пауза через $m$_nbмин';
  static const sleepActiveChapter = 'Пауза в конце главы';

  // Оглавление и скачивание
  static const voiced = 'озвучена';
  static String notVoiced(int minutes) => 'Не озвучено · ≈$_nb$minutes$_nbмин звука';
  static String downloadChapter(String dollars) => 'Скачать главу · ≈$_nb$dollars';
  static String downloading(int ready, int total) => 'Озвучиваю: готово $ready из $total$_nbмин';
  static const downloadingWhileOpen = 'Идёт, пока приложение открыто.';
  static const stopDownload = 'Остановить';
  static String downloadStrip(int percent) => 'Скачиваю главу · $percent$_nb%';
  static const stopShort = 'Стоп';
  static const downloadFailed = 'Скачивание остановилось';

  // Голос
  static const voiceTitle = 'Голос';
  static String voiceForBook(String title) => 'для книги «$title»';
  static const voiceForApp = 'для всех книг';
  static const voiceAsSettings = 'Как в настройках';
  static String voiceNow(String name) => 'сейчас $name';
  static String female(int n) => 'Женские · $n';
  static String male(int n) => 'Мужские · $n';
  static const probe = 'Проба';
  static const probeNote = 'Проба читает одну и ту же фразу. Стоит меньше цента и оплачивается один раз.';

  // Настройки
  static const settingsTitle = 'Настройки';
  static const geminiKey = 'Ключ Gemini';
  static const change = 'Изменить';
  static const whereKey = 'Где взять ключ: aistudio.google.com';
  static const needKey = 'Чтобы слушать, нужен ключ Gemini. Он вводится один раз и хранится только на телефоне.';
  static const pasteKey = 'Вставьте ключ';
  static const paste = 'Вставить';
  static const save = 'Сохранить';
  static const model = 'Модель';
  static String perHour(String dollars) => '$dollars за час звука';
  static const byDefault = 'по умолчанию';
  static const thirdCheaper = 'на треть дешевле';
  static String price2027(String a, String b) =>
      'С 1 января 2027 года Google берёт вдвое больше: $a и $b за час. Звук одной модели другой не засчитывается: '
      'после смены книги озвучиваются заново.';
  static const spent = 'Потрачено';
  static const storage = 'Озвучка на телефоне';
  static const clear = 'Очистить';
  static const storageNote = 'Озвученное второй раз не оплачивается. После очистки его придётся озвучить и оплатить заново.';
  static const clearTitle = 'Очистить озвучку?';
  static String clearBody(String size) =>
      'Удалится $size звука всех книг и проб голоса. Чтобы послушать снова, его придётся озвучить и оплатить заново.';

  static const months = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь', //
  ];

  // Форматы: числа с единицами — через неразрывный пробел (NOTES.md).
  static String mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${_num(mb / 1024, digits: 1)}$_nbГБ';
    return '${mb.round()}$_nbМБ';
  }

  static String dollars(double d) => '${d.toStringAsFixed(2).replaceAll('.', ',')}$_nb\$';

  static String _num(double v, {int digits = 2}) {
    var s = v.toStringAsFixed(digits);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s.replaceAll('.', ',');
  }

  /// Доля на полке: «новая» у неоткрытой, «100 %» у дочитанной (решение владельца 2026-11-14, FR-L4).
  static String shelfProgress(double? fraction) {
    if (fraction == null) return progressNew;
    var p = (fraction * 100).round();
    if (fraction > 0 && p == 0) p = 1;
    if (fraction < 1 && p == 100) p = 99;
    return bookPercent(p);
  }
}
