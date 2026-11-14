import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../library/library.dart';
import '../library/settings.dart';
import '../playback/chapter_download.dart';
import '../playback/narration.dart';
import '../reader/book_page.dart';
import '../reader/page_style.dart';
import '../reader/pagination.dart';
import 'common.dart';
import 'player_panel.dart';
import 'reader_sheets.dart';
import 'services.dart';
import 'settings_screen.dart';
import 'toc_screen.dart';
import 'voice_screen.dart';

/// Экран чтения (FR-R1–R8, FR-P3, FR-P4, FR-P8). Иммерсивный: только текст; панели — по касанию центра.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.services, required this.book});

  final AppServices services;
  final Book book;

  @override
  State<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  AppServices get s => widget.services;
  Book get book => widget.book;
  NarrationController get narration => s.narration;

  BookLayout? _layout;
  Object? _layoutKey;
  int _generation = 0;
  PageController? _pc;
  int _page = 0;
  bool _panels = false;
  bool _following = true;
  int? _selectedBlock;
  double? _sliderDrag;
  NarrationState _lastState = NarrationState.idle;
  late ReadingPosition _anchor;
  double _topInset = 0;
  double _bottomInset = 0;
  late PageStyle _style;
  late EdgeInsets _pad;
  late Size _column;

  /// Высота тела панели плеера (без ползунка) — страница кончается над ней. До первого замера — оценка.
  double? _playerBody;

  // Переходы по страницам. Каждый переход получает номер; завершение старого перехода не трогает признаки
  // нового. Перетаскивание пальцем сразу отменяет автоматический переход (№13 ревью).
  int _navOp = 0;

  /// Посчитана ли нынешняя раскладка с панелью плеера: если нет, а панель уже видна, раскладка вот-вот
  /// пересчитается, и листать по старой нельзя.
  bool _layoutForPlayer = false;
  bool _programmatic = false;
  int? _animatingTo;
  bool _userDragging = false;

  /// Для тестов: номер страницы и раскладка.
  int get page => _page;
  BookLayout get layout => _layout!;
  bool get panelsVisible => _panels;
  bool get following => _following;
  @visibleForTesting
  EdgeInsets get pagePadding => _pad;
  @visibleForTesting
  PageStyle get pageStyle => _style;
  @visibleForTesting
  Size get columnSize => _column;

  bool get _mine => narration.bookId == book.id && narration.state != NarrationState.idle;

  @override
  void initState() {
    super.initState();
    _anchor = _mine && narration.block != null
        ? ReadingPosition(narration.block!, 0)
        : s.library.positionOf(book.id) ?? const ReadingPosition(0, 0);
    _lastState = narration.state;
    narration.addListener(_onNarration);
    s.downloads.addListener(_rebuild);
    s.settings.addListener(_rebuild);
    s.library.addListener(_rebuild);
    setImmersive(true);
  }

  @override
  void dispose() {
    narration.removeListener(_onNarration);
    s.downloads.removeListener(_rebuild);
    s.settings.removeListener(_rebuild);
    s.library.removeListener(_rebuild);
    // Закрытие книги завершает прослушивание (А§6.6); позицию к этому моменту уже пишет контроллер.
    if (narration.bookId == book.id && narration.state != NarrationState.idle) narration.close();
    setImmersive(false);
    _flipTimer?.cancel();
    _pc?.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // --- раскладка --------------------------------------------------------------------------------------

  void _ensureLayout(PageStyle style, Size column) {
    final key = (style, column, book.id);
    if (key == _layoutKey) return;
    _layoutKey = key;
    _layout = BookLayout.compute(book: book, style: style, column: column, imageSizes: s.library.imageSizes(book.id));
    // Пока экран следует за голосом, новая раскладка (появилась или изменилась панель плеера) ставится сразу на
    // звучащее место, а не на прежний якорь: иначе звучащее оказалось бы на другой странице, и экран догонял бы его
    // анимацией поверх смены раскладки (замечание владельца 2026-11-14).
    final at = soundingPosition;
    final follow = _following && at != null && narration.state != NarrationState.idle;
    _layoutForPlayer = _mine;
    _page = follow ? _layout!.pageOf(at.block, at.offset) : _layout!.pageOf(_anchor.block, _anchor.offset);
    final old = _pc;
    _pc = PageController(initialPage: _page);
    _generation++;
    _navOp++;
    _programmatic = false;
    _animatingTo = null;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  BookPageLayout get _current => _layout!.pages[_page];

  ReadingPosition get _pagePosition => ReadingPosition(_current.firstBlock, _current.firstOffset);

  bool get _onLastPage => _page == _layout!.pages.length - 1;

  /// Доля книги на экране; на последней странице книга дочитана — 100 % (FR-L4, решение d).
  double get _fraction => _onLastPage ? 1 : book.fractionAt(_current.firstBlock, _current.firstOffset);

  // --- листание -----------------------------------------------------------------------------------------

  /// Касание правой или левой трети. Второе касание во время анимации первого не теряется: первый переход
  /// доводится мгновенно, второй идёт от него. Касание пальцем останавливает анимацию прокрутки ещё до того,
  /// как распознано как касание, поэтому цель первого перехода помнится всё время его анимации.
  void _flip(int delta) {
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    final pending = _flipTarget;
    final target = ((pending ?? _page) + delta).clamp(0, _layout!.pages.length - 1);
    if (pending != null && (pc.page ?? _page.toDouble()) != pending) {
      _navOp++;
      _programmatic = false;
      _animatingTo = null;
      pc.jumpToPage(pending);
    }
    _flipTarget = target;
    _flipTimer?.cancel();
    _flipTimer = Timer(_flipDuration, () => _flipTarget = null);
    goToPage(target);
  }

  static const _flipDuration = Duration(milliseconds: 320);
  int? _flipTarget;
  Timer? _flipTimer;

  Future<void> goToPage(int target, {bool user = true}) async {
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    target = target.clamp(0, _layout!.pages.length - 1);
    // Уже листаем туда же автоматически — не перезапускать анимацию (озвучка зовёт сюда на каждом шаге).
    if (target == _page || (!user && target == _animatingTo)) return;
    final op = ++_navOp;
    _programmatic = !user;
    if ((target - _page).abs() == 1) {
      _animatingTo = target;
      await pc.animateToPage(target, duration: _flipDuration, curve: Curves.easeOutCubic);
    } else {
      pc.jumpToPage(target);
    }
    if (op != _navOp || !mounted) return; // начался другой переход — его признаки не трогаем
    _programmatic = false;
    _animatingTo = null;
    if (pc.hasClients && pc.page != null && pc.page!.round() != _page) {
      _onPageChanged(pc.page!.round(), programmatic: !user);
    }
  }

  /// Сообщение о смене страницы от [PageView] поколения [generation]: сообщения уже заменённого (раскладка
  /// пересчиталась) не значат ничего — ни листания пользователем, ни отключения следования.
  void _onPageChangedFrom(int generation, int i) {
    if (generation != _generation) return;
    _onPageChanged(i);
  }

  void _onPageChanged(int i, {bool? programmatic}) {
    final auto = (programmatic ?? _programmatic) && !_userDragging;
    setState(() {
      _page = i;
      _anchor = _pagePosition;
      if (!auto && narration.isActive && narration.bookId == book.id) _following = false;
    });
    if (!auto) _saveScreenPosition();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      // Палец на странице: автоматический переход отменяется, следование за голосом — тоже.
      _userDragging = true;
      _flipTarget = null;
      _navOp++;
      _programmatic = false;
      _animatingTo = null;
      if (narration.isActive && narration.bookId == book.id && _following) setState(() => _following = false);
    } else if (n is ScrollEndNotification) {
      _userDragging = false;
    }
    return false;
  }

  /// Позицию пишет экран, только пока прослушивание не активно (А§5).
  void _saveScreenPosition() {
    if (narration.bookId == book.id && narration.isActive) return;
    s.library.savePosition(book.id, _pagePosition,
        fraction: _fraction, chapterTitle: chapterLabel(book, _current.chapter), atEnd: _onLastPage);
  }

  // --- следование за голосом (А§5, FR-P4) ---------------------------------------------------------------

  /// Место, которое сейчас звучит: блок и оценка смещения внутри него по доле проигранного.
  ReadingPosition? get soundingPosition {
    final block = narration.block;
    if (narration.bookId != book.id || block == null) return null;
    final len = book.blocks[block].text.length;
    final offset = math.min((narration.blockProgress.clamp(0.0, 1.0) * len).floor(), math.max(0, len - 1));
    return ReadingPosition(block, offset);
  }

  void _onNarration() {
    if (!mounted) return;
    final state = narration.state;
    if (narration.bookId == book.id) {
      if (state == NarrationState.stopped && _lastState != NarrationState.stopped) _following = true;
      final at = soundingPosition;
      // Панель плеера только что появилась или исчезла — раскладка пересчитается в этом же кадре и сама встанет
      // на звучащее место; листать по старой раскладке нельзя.
      final layoutStale = _layoutForPlayer != _mine;
      // Пока выбран абзац для «Читать отсюда», страница под пальцем не уходит за голосом (№8 проверки путей):
      // иначе кнопка исчезает, не дождавшись нажатия. Снят выбор — экран догоняет голос.
      final choosing = _selectedBlock != null;
      if (!layoutStale && !choosing && _following && at != null && _layout != null && state != NarrationState.idle) {
        final target = _layout!.pageOf(at.block, at.offset);
        if (target != _page) goToPage(target, user: false);
      }
    }
    _lastState = state;
    setState(() {});
  }

  void _backToReadingPlace() {
    setState(() => _following = true);
    _onNarration();
  }

  // --- жесты ---------------------------------------------------------------------------------------------

  void _clearSelection() {
    setState(() => _selectedBlock = null);
    _onNarration();
  }

  void _onTapUp(TapUpDetails d, Size area) {
    if (_selectedBlock != null) {
      _clearSelection();
      return;
    }
    // Знак сноски важнее панелей: видимую ссылку открываем и при открытых панелях (№12 ревью).
    final local = d.localPosition - Offset(_pad.left, _pad.top);
    final hit = hitTestPage(book: book, page: _current, style: _style, columnWidth: _column.width, p: local);
    if (hit.noteId != null) {
      showNoteSheet(context, book: book, noteId: hit.noteId!, style: _style);
      return;
    }
    if (_panels) {
      _setPanels(false);
      return;
    }
    final x = d.localPosition.dx / area.width;
    if (x < 1 / 3) {
      _flip(-1);
    } else if (x > 2 / 3) {
      _flip(1);
    } else {
      _setPanels(true);
    }
  }

  void _onLongPress(LongPressStartDetails d) {
    final local = d.localPosition - Offset(_pad.left, _pad.top);
    final hit = hitTestPage(book: book, page: _current, style: _style, columnWidth: _column.width, p: local);
    final b = hit.block;
    if (b == null || !book.blocks[b].isSpoken) return;
    _setPanels(false);
    setState(() => _selectedBlock = b);
  }

  void _setPanels(bool v) {
    setState(() => _panels = v);
    setImmersive(!v);
  }

  // --- действия -------------------------------------------------------------------------------------------

  /// Переход на другой экран: строка состояния там нужна, иммерсивный режим — только у чтения.
  Future<T?> _push<T>(Widget screen) async {
    setImmersive(false);
    final result = await Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen));
    if (mounted) setImmersive(!_panels);
    return result;
  }

  bool _requireKey() {
    if (s.settings.hasApiKey) return true;
    // Нет ключа: «Слушать» ведёт в настройки на поле ключа (FR-P7).
    _push<void>(SettingsScreen(services: s, focusKey: true));
    return false;
  }

  /// «Слушать» (FR-P3): экран только сообщает видимую страницу, место выбирает контроллер. Следование включено
  /// сразу: кнопки «К месту чтения» после старта быть не может.
  void listen() {
    if (!_requireKey()) return;
    final page = PageRange(_pagePosition, ReadingPosition(_current.lastBlock, _current.lastEnd));
    _following = true;
    narration.listen(book, page);
    _setPanels(false);
  }

  void readFrom(int block) {
    if (!_requireKey()) return;
    setState(() {
      _selectedBlock = null;
      _following = true;
    });
    narration.readFrom(book, block);
  }

  /// Действия, которыми пользователь сам запускает или меняет место звука, включают следование за голосом
  /// (решение a): «Слушать» из паузы и из панели ошибки, «назад», «вперёд». Выключают его только ручное листание
  /// и ползунок.
  void _withFollowing(VoidCallback command) {
    setState(() => _following = true);
    command();
    _onNarration();
  }

  void _play() => _withFollowing(narration.resume);
  void _previous() => _withFollowing(narration.previous);
  void _next() => _withFollowing(narration.next);

  void _closeNarration() {
    // «Закрыть» — одна команда контроллера: сеанс завершён, затем позиция чтения — место на экране — отдана
    // писателю (FR-P8). Панель уходит, страница становится длиннее и пересчитывается так, чтобы это место
    // осталось на экране: если экран следовал за голосом — звучавшее место, иначе — начало страницы, которую
    // пользователь листал сам. Прежде бралось начало страницы, и пересчёт уводил экран назад, туда, где звучавшего
    // абзаца уже не было (замечание владельца 2026-11-14). На последней странице книга остаётся дочитанной.
    final place = (_following ? soundingPosition : null) ?? _pagePosition;
    _anchor = place;
    narration.close(screenPosition: place, screenAtEnd: _onLastPage);
    setState(() => _following = true);
  }

  Future<void> _openContents() async {
    final chapter = await _push<int>(TocScreen(services: s, book: book, current: _current.chapter));
    if (chapter == null || !mounted) return;
    _setPanels(false);
    final listening = narration.bookId == book.id &&
        (narration.isActive || narration.state == NarrationState.paused);
    if (listening) {
      // Во время прослушивания выбор главы — новое место звука: голос к началу главы (и текущей тоже), следование
      // включено, страницу ведёт голос — переход не считается ручным листанием (№1 проверки путей, решение a).
      _withFollowing(() => narration.moveIfListening(book, book.chapters[chapter].firstBlock));
    } else {
      await goToPage(_layout!.chapterFirstPage[chapter]);
    }
  }

  /// Отказ по ключу: «Изменить ключ» ведёт к полю ключа в настройках; «Назад» возвращает в книгу (FR-P7).
  Future<void> _changeKey() => _push<void>(SettingsScreen(services: s, focusKey: true));

  Future<void> _openVoice() => _push<void>(VoiceScreen(services: s, book: book));

  // --- построение ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final step = fontSteps[s.settings.fontStep];
    _style = PageStyle(fontSize: step.size, lineHeight: step.lineHeight, textScaler: media.textScaler);
    _topInset = math.max(_topInset, media.viewPadding.top);
    _bottomInset = math.max(_bottomInset, media.viewPadding.bottom);
    final task = s.downloads.task;
    final downloading = task != null && task.bookId == book.id && task.status == DownloadStatus.running;
    final downloadLine = downloading ? DownloadLine(task: task, onStop: s.downloads.stop) : null;
    // Системная «Назад» сначала закрывает временное — выбор абзаца, панели чтения (листы и диалоги — свои
    // маршруты, их закрывает навигатор), и только потом книгу (решение f, А§8.1).
    return PopScope(
      canPop: _selectedBlock == null && !_panels,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedBlock != null) {
          _clearSelection();
        } else if (_panels) {
          _setPanels(false);
        }
      },
      child: _scaffold(context, downloadLine, downloading: downloading),
    );
  }

  Widget _scaffold(BuildContext context, DownloadLine? downloadLine, {required bool downloading}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final colors = PageColors(
      ink: scheme.onSurface,
      ink2: scheme.onSurfaceVariant,
      accent: scheme.primary,
      highlight: scheme.primaryContainer,
      rule: scheme.outlineVariant,
    );
    return Scaffold(
      backgroundColor: scheme.surface,
      body: LayoutBuilder(builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        final playerVisible = _mine;
        // Страница кончается над всем, что занято внизу постоянно: панелью плеера (вместе с её строкой
        // скачивания и «К месту чтения») или строкой скачивания и долей книги.
        final reserved = playerVisible
            ? (_playerBody ?? PlayerPanel.controlsHeight + _bottomInset) + 16
            : _bottomInset + (downloading ? 104 : 44);
        _pad = EdgeInsets.fromLTRB(24, _topInset + 28, 24, reserved);
        _column = Size(area.width - _pad.horizontal, math.max(_style.lineHeight * 3, area.height - _pad.vertical));
        _ensureLayout(_style, _column);
        final generation = _generation;
        final highlight = <int>{
          if (playerVisible && narration.block != null) narration.block!,
          ?_selectedBlock,
        };
        final previewChapter = _sliderDrag == null ? _current.chapter : book.chapterOf(book.placeAt(_sliderDrag!).$1);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('page-area'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTapUp(d, area),
                onLongPressStart: _onLongPress,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: PageView.builder(
                    key: ValueKey('pages-$_generation'),
                    controller: _pc,
                    onPageChanged: (i) => _onPageChangedFrom(generation, i),
                    itemCount: _layout!.pages.length,
                    itemBuilder: (context, i) => ColoredBox(
                      color: scheme.surface,
                      child: Padding(
                        padding: _pad,
                        child: BookPage(
                          key: ValueKey('page-$i'),
                          book: book,
                          page: _layout!.pages[i],
                          style: _style,
                          colors: colors,
                          imageFor: (id) => s.library.image(book.id, id),
                          highlightBlocks: highlight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_panels && !playerVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: _bottomInset + 14,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (downloadLine != null) ...[downloadLine, const SizedBox(height: 12)],
                  IgnorePointer(
                    child: Text(l10n.percent(_fraction),
                        key: const Key('footer-percent'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ]),
              ),
            if (_selectedBlock != null) _readFromHere(context, area),
            _Slide(
              visible: _panels,
              from: const Offset(0, -1),
              alignment: Alignment.topCenter,
              child: _TopBar(
                title: book.title,
                subtitle: book.chapters[previewChapter].title.isEmpty ? null : chapterLabel(book, previewChapter),
                // Кнопка «Назад» в шапке закрывает книгу сразу; системная «Назад» сначала убирает временное (f).
                onBack: () => Navigator.of(context).pop(),
                onContents: _openContents,
                onAppearance: () => showTextAppearanceSheet(context, s.settings, s.themePreviews),
                onTitleLongPress: s.openDemoStates == null ? null : () => s.openDemoStates!(context),
              ),
            ),
            if (!playerVisible)
              _Slide(
                visible: _panels,
                from: const Offset(0, 1),
                alignment: Alignment.bottomCenter,
                child: _BottomPanel(
                  slider: _sliderStrip(context),
                  download: _panels ? downloadLine : null,
                  voiceName: s.library.bookVoice(book.id) ?? s.settings.voice,
                  onVoice: _openVoice,
                  onListen: listen,
                  bottomInset: _bottomInset,
                ),
              ),
            if (playerVisible)
              Align(
                alignment: Alignment.bottomCenter,
                child: PlayerPanel(
                  narration: narration,
                  settings: s.settings,
                  voiceName: s.library.bookVoice(book.id) ?? s.settings.voice,
                  following: _following,
                  onBackToReading: _backToReadingPlace,
                  onClose: _closeNarration,
                  onVoice: _openVoice,
                  onSpeed: () => showSpeedSheet(context, s.settings, narration),
                  onSleep: () => showSleepSheet(context, narration),
                  onTopUp: () => s.openUrl(context, billingUrl),
                  onChooseModel: () => _push<void>(SettingsScreen(services: s, openModel: true)),
                  onChangeKey: _changeKey,
                  onPlay: _play,
                  onPrevious: _previous,
                  onNext: _next,
                  header: _panels ? _sliderStrip(context) : null,
                  download: downloadLine,
                  onBodyHeight: (h) {
                    if (_playerBody == null || (h - _playerBody!).abs() > 0.5) setState(() => _playerBody = h);
                  },
                ),
              ),
          ],
        );
      }),
    );
  }

  /// Ползунок по книге и доля. Название главы — только в шапке; при перетаскивании шапка показывает главу,
  /// в которую попадёт палец.
  Widget _sliderStrip(BuildContext context) {
    final theme = Theme.of(context);
    final value = _sliderDrag ?? _fraction;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(context.l10n.ofBook(value),
                textAlign: TextAlign.end, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface)),
          ),
          Slider(
            key: const Key('book-slider'),
            value: value.clamp(0.0, 1.0),
            // Внешний вид Material 3 2024 года; флаг помечен устаревшим, но другого способа включить его нет.
            // ignore: deprecated_member_use
            year2023: false,
            onChanged: (v) => setState(() => _sliderDrag = v),
            onChangeEnd: (v) {
              final (b, o) = book.placeAt(v);
              setState(() => _sliderDrag = null);
              goToPage(_layout!.pageOf(b, o));
            },
          ),
        ],
      ),
    );
  }

  /// «Читать отсюда» — у абзаца, но всегда в видимой части экрана: не за его краем и не под панелью плеера.
  Widget _readFromHere(BuildContext context, Size area) {
    final frags = _current.fragments.where((f) => f.block == _selectedBlock).toList();
    if (frags.isEmpty) return const SizedBox.shrink();
    const button = 48.0;
    final top = _pad.top + frags.first.top;
    final bottom = _pad.top + frags.last.top + frags.last.height;
    final minY = _topInset + 8;
    final maxY = area.height - _pad.bottom - button - 8;
    final double y = (top - button - 12 >= minY ? top - button - 12 : bottom + 12).clamp(minY, math.max(minY, maxY));
    return Positioned(
      left: 0,
      right: 0,
      top: y,
      child: Center(
        child: FilledButton.icon(
          key: const Key('read-from-here'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, button),
            elevation: 6,
            shadowColor: Theme.of(context).colorScheme.shadow,
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          onPressed: () => readFrom(_selectedBlock!),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.l10n.readFromHere),
        ),
      ),
    );
  }
}

/// Плавное появление панели: сдвиг + прозрачность; спрятанная панель не ловит касания.
class _Slide extends StatelessWidget {
  const _Slide({required this.visible, required this.from, required this.alignment, required this.child});

  final bool visible;
  final Offset from;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : from,
          duration: const Duration(milliseconds: 260),
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onContents,
    required this.onAppearance,
    this.onTitleLongPress,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onContents;
  final VoidCallback onAppearance;
  final VoidCallback? onTitleLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Material(
      key: const Key('reader-top-bar'),
      color: scheme.surfaceContainer,
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onLongPress: onTitleLongPress,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Название книги может сокращаться (исключение FR-R8), название главы — переносится.
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                        if (subtitle != null)
                          Text(subtitle!,
                              key: const Key('top-bar-chapter'),
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(tooltip: l10n.contents, icon: const Icon(Icons.toc_rounded), onPressed: onContents),
              IconButton(
                  tooltip: l10n.textAppearance, icon: const Icon(Icons.text_fields_rounded), onPressed: onAppearance),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.slider,
    required this.download,
    required this.voiceName,
    required this.onVoice,
    required this.onListen,
    required this.bottomInset,
  });

  final Widget slider;
  final Widget? download;
  final String voiceName;
  final VoidCallback onVoice;
  final VoidCallback onListen;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Material(
      key: const Key('reader-bottom-panel'),
      color: scheme.surfaceContainer,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 14, 0, bottomInset + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            slider,
            if (download != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: download),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Голос книги — и до первого прослушивания (FR-V2).
                  VoiceChip(key: const Key('voice-chip-idle'), voiceName: voiceName, onPressed: onVoice),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: FilledButton.icon(
                key: const Key('listen'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56), textStyle: Theme.of(context).textTheme.titleMedium),
                onPressed: onListen,
                icon: const Icon(Icons.headphones_rounded),
                label: Text(l10n.listen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пока идёт «Скачать главу» — короткая строка с долей готового и «Стоп» (решение владельца 2026-11-14, FR-D2).
/// Видна всегда: в подвале страницы, в нижней панели и в панели плеера.
class DownloadLine extends StatelessWidget {
  const DownloadLine({super.key, required this.task, required this.onStop});

  final ChapterDownloadTask task;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const Key('download-strip'),
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(value: task.fraction, strokeWidth: 3, backgroundColor: scheme.outlineVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(context.l10n.downloadStrip(task.fraction), style: theme.textTheme.bodyMedium),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onStop,
            child: Text(context.l10n.stopShort),
          ),
        ]),
      ),
    );
  }
}
