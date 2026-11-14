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
import 'strings.dart';
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
  bool _programmatic = false;
  int? _animatingTo;
  NarrationState _lastState = NarrationState.idle;
  late ReadingPosition _anchor;
  double _topInset = 0;
  double _bottomInset = 0;
  late PageStyle _style;
  late EdgeInsets _pad;
  late Size _column;

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
    setImmersive(true);
  }

  @override
  void dispose() {
    narration.removeListener(_onNarration);
    s.downloads.removeListener(_rebuild);
    s.settings.removeListener(_rebuild);
    // Закрытие книги завершает прослушивание (А§6.6).
    if (narration.bookId == book.id && narration.state != NarrationState.idle) {
      narration.close();
    }
    setImmersive(false);
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
    _page = _layout!.pageOf(_anchor.block, _anchor.offset);
    final old = _pc;
    _pc = PageController(initialPage: _page);
    _generation++;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  BookPageLayout get _current => _layout!.pages[_page];

  ReadingPosition get _pagePosition => ReadingPosition(_current.firstBlock, _current.firstOffset);

  double get _fraction => book.fractionAt(_current.firstBlock, _current.firstOffset);

  // --- листание -----------------------------------------------------------------------------------------

  Future<void> goToPage(int target, {bool user = true}) async {
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    target = target.clamp(0, _layout!.pages.length - 1);
    // Уже листаем туда же — не перезапускать анимацию (озвучка зовёт сюда на каждом своём шаге).
    if (target == _page || target == _animatingTo) return;
    _programmatic = !user;
    if ((target - _page).abs() == 1) {
      _animatingTo = target;
      await pc.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      if (_animatingTo == target) _animatingTo = null;
    } else {
      pc.jumpToPage(target);
    }
    _programmatic = false;
    // Номер страницы — по контроллеру: уведомление о смене страницы приходит не при каждом переходе.
    if (mounted && pc.hasClients && pc.page != null && pc.page!.round() != _page) {
      _onPageChanged(pc.page!.round(), programmatic: !user);
    }
  }

  void _onPageChanged(int i, {bool? programmatic}) {
    final auto = programmatic ?? _programmatic;
    setState(() {
      _page = i;
      _anchor = _pagePosition;
      if (!auto && narration.isActive && narration.bookId == book.id) _following = false;
    });
    if (!auto) _saveScreenPosition();
  }

  /// Позицию пишет экран, только пока прослушивание не активно (А§5).
  void _saveScreenPosition() {
    if (narration.bookId == book.id && narration.isActive) return;
    s.library.savePosition(book.id, _pagePosition,
        fraction: _fraction, chapterTitle: chapterLabel(book, _current.chapter));
  }

  // --- следование за голосом (А§5, FR-P4) ---------------------------------------------------------------

  void _onNarration() {
    if (!mounted) return;
    final state = narration.state;
    if (narration.bookId == book.id) {
      if (state == NarrationState.stopped && _lastState != NarrationState.stopped) _following = true;
      final block = narration.block;
      if (_following && block != null && _layout != null && state != NarrationState.idle) {
        final len = book.blocks[block].text.length;
        final offset = (narration.blockProgress.clamp(0.0, 1.0) * len).floor();
        final target = _layout!.pageOf(block, offset);
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

  void _onTapUp(TapUpDetails d, Size area) {
    if (_selectedBlock != null) {
      setState(() => _selectedBlock = null);
      return;
    }
    if (_panels) {
      _setPanels(false);
      return;
    }
    final local = d.localPosition - Offset(_pad.left, _pad.top);
    final hit = hitTestPage(book: book, page: _current, style: _style, columnWidth: _column.width, p: local);
    if (hit.noteId != null) {
      showNoteSheet(context, book: book, noteId: hit.noteId!, style: _style);
      return;
    }
    final x = d.localPosition.dx / area.width;
    if (x < 1 / 3) {
      goToPage(_page - 1);
    } else if (x > 2 / 3) {
      goToPage(_page + 1);
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

  void listen() {
    if (!_requireKey()) return;
    // Первый абзац, который начинается на этой странице; хвост абзаца с прошлой страницы не считается —
    // иначе страница сразу уехала бы назад, к его началу.
    final starts = _current.fragments.where((f) => f.start == 0 && book.blocks[f.block].isSpoken);
    final first = starts.isNotEmpty
        ? starts.first.block
        : _current.fragments.map((f) => f.block).firstWhere((b) => book.blocks[b].isSpoken,
            orElse: () => _current.firstBlock);
    narration.start(book, first);
    _following = true;
    _setPanels(false);
  }

  void readFrom(int block) {
    if (!_requireKey()) return;
    setState(() {
      _selectedBlock = null;
      _following = true;
    });
    narration.start(book, block);
  }

  void _closeNarration() {
    // «Закрыть»: idle, позиция — начало страницы на экране (FR-P8). Панель уходит, страница становится длиннее
    // и пересчитывается от этого же места.
    final position = _pagePosition;
    s.library.savePosition(book.id, position, fraction: _fraction, chapterTitle: chapterLabel(book, _current.chapter));
    _anchor = position;
    narration.close();
    setState(() => _following = true);
  }

  Future<void> _openContents() async {
    final chapter = await _push<int>(TocScreen(services: s, book: book, current: _current.chapter));
    if (chapter == null || !mounted) return;
    final target = _layout!.chapterFirstPage[chapter];
    if (_mine && narration.isActive) {
      final wasPaused = narration.state == NarrationState.paused;
      narration.start(book, book.chapters[chapter].firstBlock);
      if (wasPaused) narration.pause();
      _following = true;
    }
    _setPanels(false);
    await goToPage(target);
  }

  Future<void> _openVoice() async {
    // Открытие экрана голоса ставит прослушивание на паузу (FR-V1).
    narration.pause();
    await _push<void>(VoiceScreen(services: s, book: book));
  }

  // --- построение ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final step = fontSteps[s.settings.fontStep];
    _style = PageStyle(fontSize: step.size, lineHeight: step.lineHeight, textScaler: media.textScaler);
    _topInset = math.max(_topInset, media.viewPadding.top);
    _bottomInset = math.max(_bottomInset, media.viewPadding.bottom);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = PageColors(
      ink: scheme.onSurface,
      ink2: scheme.onSurfaceVariant,
      accent: scheme.primary,
      highlight: scheme.primaryContainer,
    );
    return Scaffold(
      backgroundColor: scheme.surface,
      body: LayoutBuilder(builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        final playerVisible = _mine;
        // Пока видна панель плеера, страница кончается над ней: под панелью текст не прячется.
        _pad = EdgeInsets.fromLTRB(
            24, _topInset + 28, 24, _bottomInset + (playerVisible ? PlayerPanel.controlsHeight + 16 : 44));
        _column = Size(area.width - _pad.horizontal, math.max(_style.lineHeight * 3, area.height - _pad.vertical));
        _ensureLayout(_style, _column);
        final highlight = <int>{
          if (playerVisible && narration.block != null) narration.block!,
          ?_selectedBlock,
        };
        final task = s.downloads.task;
        final showStrip = task != null && task.bookId == book.id && task.status == DownloadStatus.running;
        final showToPlace = playerVisible && narration.isActive && !_following;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('page-area'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTapUp(d, area),
                onLongPressStart: _onLongPress,
                child: PageView.builder(
                  key: ValueKey('pages-$_generation'),
                  controller: _pc,
                  onPageChanged: _onPageChanged,
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
            if (!_panels && !playerVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: _bottomInset + 14,
                child: IgnorePointer(
                  child: Text(S.bookPercent((_fraction * 100).round()),
                      key: const Key('footer-percent'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ),
            if (_selectedBlock != null) _readFromHere(context),
            _Slide(
              visible: _panels,
              from: const Offset(0, -1),
              alignment: Alignment.topCenter,
              child: _TopBar(
                title: book.title,
                subtitle: chapterLabel(book, _current.chapter),
                onBack: () => Navigator.of(context).maybePop(),
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
                  slider: _sliderStrip(context, compact: false),
                  onListen: listen,
                  bottomInset: _bottomInset,
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showToPlace)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FilledButton.tonalIcon(
                          key: const Key('to-reading-place'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            elevation: 3,
                            shadowColor: scheme.shadow,
                          ),
                          onPressed: _backToReadingPlace,
                          icon: const Icon(Icons.my_location_rounded),
                          label: const Text(S.toReadingPlace),
                        ),
                      ),
                    ),
                  if (showStrip && !_panels)
                    _DownloadStrip(task: task, onStop: s.downloads.stop, bottomInset: playerVisible ? 0 : _bottomInset),
                  if (playerVisible) ...[
                    PlayerPanel(
                      narration: narration,
                      settings: s.settings,
                      voiceName: s.library.bookVoice(book.id) ?? s.settings.voice,
                      chapterTitle: chapterLabel(book, book.chapterOf(narration.block ?? _current.firstBlock)),
                      onClose: _closeNarration,
                      onVoice: _openVoice,
                      onSpeed: () => showSpeedSheet(context, s.settings, narration),
                      onSleep: () => showSleepSheet(context, narration),
                      onTopUp: () => s.openUrl(context, S.billingUrl),
                      onChooseModel: () => _push<void>(SettingsScreen(services: s, openModel: true)),
                      header: _panels ? _sliderStrip(context, compact: true) : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _sliderStrip(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = _sliderDrag ?? _fraction;
    final (pb, _) = book.placeAt(value);
    final label = _sliderDrag == null ? chapterLabel(book, _current.chapter) : chapterLabel(book, book.chapterOf(pb));
    final strip = Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 10 : 4, 20, compact ? 4 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 12),
              Text(S.ofBook((value * 100).round()),
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
            ]),
          ),
          Slider(
            key: const Key('book-slider'),
            value: value.clamp(0.0, 1.0),
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
    return strip;
  }

  Widget _readFromHere(BuildContext context) {
    final frags = _current.fragments.where((f) => f.block == _selectedBlock).toList();
    if (frags.isEmpty) return const SizedBox.shrink();
    final top = _pad.top + frags.first.top;
    final bottom = _pad.top + frags.last.top + frags.last.height;
    final above = top > _pad.top + 64;
    return Positioned(
      left: 0,
      right: 0,
      top: above ? top - 60 : bottom + 8,
      child: Center(
        child: FilledButton.icon(
          key: const Key('read-from-here'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            elevation: 6,
            shadowColor: Theme.of(context).colorScheme.shadow,
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          onPressed: () => readFrom(_selectedBlock!),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text(S.readFromHere),
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
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onContents;
  final VoidCallback onAppearance;
  final VoidCallback? onTitleLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            children: [
              IconButton(tooltip: S.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onLongPress: onTitleLongPress,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              IconButton(tooltip: S.contents, icon: const Icon(Icons.toc_rounded), onPressed: onContents),
              IconButton(
                  tooltip: S.textAppearance, icon: const Icon(Icons.text_fields_rounded), onPressed: onAppearance),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.slider, required this.onListen, required this.bottomInset});

  final Widget slider;
  final VoidCallback onListen;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: FilledButton.icon(
                key: const Key('listen'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: Theme.of(context).textTheme.titleMedium),
                onPressed: onListen,
                icon: const Icon(Icons.headphones_rounded),
                label: const Text(S.listen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пока идёт «Скачать главу» — короткая строка с долей готового и «Стоп» (решение владельца 2026-11-14, FR-D2).
class _DownloadStrip extends StatelessWidget {
  const _DownloadStrip({required this.task, required this.onStop, required this.bottomInset});

  final ChapterDownloadTask task;
  final VoidCallback onStop;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 8),
      child: Material(
        key: const Key('download-strip'),
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: Row(children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(value: task.fraction, strokeWidth: 3, backgroundColor: scheme.outlineVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(S.downloadStrip((task.fraction * 100).round()),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
            TextButton(onPressed: onStop, child: const Text(S.stopShort)),
          ]),
        ),
      ),
    );
  }
}
