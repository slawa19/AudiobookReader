import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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

/// The reading screen (FR-R1–R8, FR-P3, FR-P4, FR-P8). Immersive: text only; panels — on a tap in the center.
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

  ChapterPagination? _layout;
  ChapterPagination? _pendingLayout;
  ReadingPosition? _pendingGoal;
  ({PageStyle style, Size column, EdgeInsets pad})? _shownMetrics;
  ({PageStyle style, Size column, EdgeInsets pad})? _pendingMetrics;
  late ({PageStyle style, Size column, EdgeInsets pad}) _wantedMetrics;
  bool _pendingSave = true;
  bool _pendingMove = false;
  bool _pendingUser = false;
  // A nearby programmatic target continues the layout instead of a new start from the block.
  static const _nearbyLayoutChars = 30000;
  int _seenPrepend = 0;
  int? _waitingPage;
  bool _waitingUser = true;
  Completer<void>? _waitingDone;
  Object? _layoutKey;
  int _generation = 0;
  PageController? _pc;
  int _page = 0;
  bool _panels = false;
  int _panelsVersion = 0;
  bool _following = true;
  int? _selectedBlock;
  double? _sliderDrag;
  NarrationState _lastState = NarrationState.idle;
  late ReadingPosition _anchor;
  ReadingPosition? _heldAfterClose;
  double _topInset = 0;
  double _bottomInset = 0;
  late PageStyle _style;
  late EdgeInsets _pad;
  late Size _column;

  /// Error messages and the download are measured by content; the controls have a constant height.
  double? _messageBody;

  // Page transitions. Each transition gets a number; the completion of an old transition does not touch the flags
  // of the new one. Dragging with a finger immediately cancels the automatic transition (review item 13).
  int _navOp = 0;

  bool _programmatic = false;
  int? _animatingTo;
  bool _userDragging = false;

  /// The page from which a finger gesture began; `null` — no gesture. Following is turned off only by a gesture that
  /// actually changed the page (logic review decision 2026-11-14).
  int? _dragStartPage;
  bool _dragWaiting = false;
  VelocityTracker? _edgeVelocity;
  double _pointerStartX = 0;
  double _pointerTravel = 0;
  int _edgeSide = 0;
  int _pointerPage = 0;

  /// The place of the selected paragraph on the page where it was selected: re-layout keeps it on screen (logic review
  /// item 3).
  ReadingPosition? _selectedAt;

  /// The last seen counter of explicit controller commands (A§5): if it changed — following is turned on.
  int _seenCommands = 0;
  ReadingPosition? _lastSounding;

  /// A finger grabbed the page during an automatic page turn after the voice: following is turned off even if
  /// the page came back (gesture review decision C).
  bool _grabbedAuto = false;

  /// Protection against a follow-up touch (gesture review decision A, A§8.1): after the layer under the finger changes,
  /// the screen does not accept touches for [layerSettleTime].
  bool _guarded = true;
  Timer? _guardTimer;
  Object? _layerSignature;

  /// For tests: the page number and the layout.
  int get page => _page;
  ChapterPagination get layout => _layout!;
  bool get panelsVisible => _panels;
  bool get following => _following;
  @visibleForTesting
  bool get gestureInProgress => _dragStartPage != null;
  @visibleForTesting
  EdgeInsets get pagePadding => _pad;
  @visibleForTesting
  PageStyle get pageStyle => _style;
  @visibleForTesting
  Size get columnSize => _column;

  bool get _mine => narration.bookId == book.id && narration.state != NarrationState.idle;

  // A new page size blocks old gestures; a nearby target in the same layout does not.
  bool get _reflowing => _pendingLayout != null && !identical(_pendingLayout, _layout);

  @override
  void initState() {
    super.initState();
    _anchor = _mine && narration.block != null
        ? ReadingPosition(narration.block!, 0)
        : s.library.positionOf(book.id) ?? const ReadingPosition(0, 0);
    _lastState = narration.state;
    _seenCommands = narration.commandRevision;
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
    // Closing the book ends listening (A§6.6); the controller already writes the position by this time.
    if (narration.bookId == book.id && narration.state != NarrationState.idle) narration.close();
    unawaited(s.flush());
    setImmersive(false);
    _flipTimer?.cancel();
    _guardTimer?.cancel();
    _pc?.dispose();
    _layout?.dispose();
    if (!identical(_pendingLayout, _layout)) _pendingLayout?.dispose();
    _waitingDone?.complete();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The layer under the finger changed: touches are not accepted for [layerSettleTime]. Called from build (panel
  /// change) and after closing a sheet, a dialog or a screen on top of reading.
  void _guardLayer() {
    _guarded = true;
    _guardTimer?.cancel();
    _guardTimer = Timer(layerSettleTime, () {
      if (mounted) setState(() => _guarded = false);
    });
  }

  /// A sheet, a dialog or a screen on top of reading closed — what was under it gets protection against a follow-up
  /// touch.
  Future<T?> _afterLayer<T>(Future<T?> layer) async {
    final result = await layer;
    if (mounted) setState(_guardLayer);
    return result;
  }

  // --- layout -----------------------------------------------------------------------------------------

  void _ensureLayout(PageStyle style, Size column) {
    final key = (style, column, book.id);
    if (key == _layoutKey) return;
    _layoutKey = key;
    final at = soundingPosition;
    final follow = _following && at != null && narration.state != NarrationState.idle;
    final closing = _heldAfterClose != null;
    final pending = _pendingGoal;
    final pendingMove = _pendingMove;
    final pendingUser = _pendingUser;
    final pendingSave = _pendingSave;
    final held = _selectedAt ?? (follow ? at : pending ?? _heldAfterClose);
    _heldAfterClose = null;
    final visible = _layout == null ? null : _current;
    final retain = held != null && visible != null && visible.contains(held.block, held.offset);
    // The held place defines visibility, and the start remains from the already shown page.
    final from = visible != null && (held == null || retain)
        ? ReadingPosition(visible.firstBlock, visible.firstOffset)
        : held == null ? _anchor : ReadingPosition(held.block, 0);
    // "Close" already passed the position through the controller (FR-P8); a single re-layout does not overwrite it.
    _startLayout(from, retain: held, completeRetain: retain,
        savePosition: !closing && (pending == null || pendingSave),
        move: pending != null && pendingMove, user: pending != null && pendingUser);
  }

  /// Saved line starts are preserved exactly. For another target the caller passes the block start
  /// and the held position; the search for its page also goes in batches, even inside a long paragraph.
  void _startLayout(ReadingPosition place, {ReadingPosition? retain, bool completeRetain = false,
      bool savePosition = true, bool move = false, bool user = false}) {
    _cancelPending();
    _layout?.pause();
    final metrics = _wantedMetrics;
    final next = ChapterPagination();
    next.start(book: book, style: metrics.style, column: metrics.column, block: place.block, offset: place.offset,
        throughBook: true, imageSizes: s.library.imageSizes(book.id));
    // Up to the held place — no more than the text of one previous page. The first suitable page
    // is shown at once, without an intermediate display of the page the voice has already left.
    while (completeRetain && retain != null && next.findPage(retain.block, retain.offset) == null && !next.isComplete) {
      next.advancePage();
    }
    _cancelPageRequest();
    final target = retain == null ? 0 : next.findPage(retain.block, retain.offset);
    if (target != null) {
      _installLayout(next, target, metrics, savePosition: savePosition, move: move, user: user);
      return;
    }
    _pendingLayout = next;
    _pendingGoal = retain;
    _pendingMetrics = metrics;
    _pendingSave = savePosition;
    _pendingMove = move;
    _pendingUser = user;
    if (_layout == null) {
      _layout = next;
      _page = 0;
      _shownMetrics = metrics;
      _seenPrepend = 0;
    }
    _resetPages();
    next.addListener(_onPendingLayout);
  }

  void _cancelPending() {
    final pending = _pendingLayout;
    _pendingLayout = null;
    _pendingGoal = null;
    if (pending == null) return;
    pending.removeListener(_onPendingLayout);
    if (identical(pending, _layout)) {
      // The search may have temporarily taken the listener from the shown layout. Any cancellation returns it.
      pending.removeListener(_onLayout);
      pending.addListener(_onLayout);
    } else {
      pending.dispose();
    }
  }

  void _cancelPageRequest() {
    _layout?.cancelPrevious();
    _waitingPage = null;
    _waitingDone?.complete();
    _waitingDone = null;
    _flipTarget = null;
    _flipTimer?.cancel();
    _navOp++;
  }

  void _onPendingLayout() {
    if (!mounted) return;
    final pending = _pendingLayout!;
    final goal = _pendingGoal!;
    final target = pending.findPage(goal.block, goal.offset, preferredPage: identical(pending, _layout) ? _page : null);
    if (target == null && identical(pending, _layout) && !pending.isLoadingPrevious &&
        (pending.isComplete || pending.pages.last.chapter > book.chapterOf(goal.block))) {
      // The catch-up exhausted the chapter without a target — an ordinary search from its block.
      _startLayout(ReadingPosition(goal.block, 0), retain: goal,
          savePosition: _pendingSave, move: _pendingMove, user: _pendingUser);
      return;
    }
    if (target == null && (pending.isLoadingPrevious || !pending.isComplete)) {
      setState(() {});
      return;
    }
    setState(() => _installLayout(pending, target ?? pending.pages.length - 1, _pendingMetrics!,
        savePosition: _pendingSave, move: _pendingMove, user: _pendingUser));
  }

  void _installLayout(ChapterPagination next, int target,
      ({PageStyle style, Size column, EdgeInsets pad}) metrics,
      {required bool savePosition, required bool move, required bool user}) {
    next.removeListener(_onPendingLayout);
    next.removeListener(_onLayout);
    final old = _layout;
    if (old != null && !identical(old, next)) {
      old.removeListener(_onLayout);
      old.dispose();
    }
    _pendingLayout = null;
    _pendingGoal = null;
    _layout = next;
    _shownMetrics = metrics;
    _seenPrepend = next.prependedCount;
    _page = target;
    _anchor = _pagePosition;
    next.addListener(_onLayout);
    next.resume();
    _resetPages();
    _markLastAfterFrame();
    final generation = _generation;
    // In stopped the controller position stays until the reader explicitly moves (A§5).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (move) _reportShownPage();
      if (user || (savePosition && !_mine)) _saveScreenPosition();
    });
  }

  void _resetPages() {
    final old = _pc;
    _pc = PageController(initialPage: _page);
    _generation++;
    _navOp++;
    _programmatic = false;
    _animatingTo = null;
    _dragStartPage = null;
    _dragWaiting = false;
    _edgeSide = 0;
    _userDragging = false;
    _grabbedAuto = false;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _markLastAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _onLastPage) s.library.setFinished(book.id, true);
    });
  }

  void _onLayout() {
    if (!mounted) return;
    final added = layout.prependedCount - _seenPrepend;
    setState(() {
      if (added > 0) {
        _seenPrepend = layout.prependedCount;
        _page += added;
        if (_waitingPage != null) _waitingPage = _waitingPage! + added;
        if (_flipTarget != null) _flipTarget = _flipTarget! + added;
        // An insertion before the array changes only the local index, not the visible text.
        _resetPages();
      }
    });
    _markLastAfterFrame();
    if (identical(_pendingLayout, _layout)) {
      _onPendingLayout();
      return;
    }
    final waiting = _waitingPage;
    if (waiting == null) return;
    if (waiting < 0 && layout.hasPrevious) {
      unawaited(layout.loadPrevious());
      return;
    }
    if (waiting >= layout.pages.length && !layout.isComplete) return;
    final done = _waitingDone;
    final user = _waitingUser;
    _waitingPage = null;
    _waitingDone = null;
    _dragStartPage = null;
    _userDragging = false;
    _onPageChanged(waiting.clamp(0, layout.pages.length - 1), programmatic: !user);
    setState(_resetPages);
    done?.complete();
  }

  void _goToPlace(int block, int offset, {bool user = true}) {
    final target = layout.findPage(block, offset, preferredPage: _page);
    final changingMetrics = _pendingLayout != null && _pendingMetrics != _shownMetrics;
    if (!changingMetrics && target != null &&
        (!user || target == _page)) {
      // Returning to any already computed place keeps the page and the text position (A§5).
      _goToCalculatedPage(target, user: user);
      return;
    }
    if (_pendingLayout != null) {
      if (_current.contains(block, offset)) {
        setState(() => _startLayout(_pagePosition, retain: ReadingPosition(block, offset), completeRetain: true));
      } else {
        goToPosition(ReadingPosition(block, offset), user: user);
      }
      return;
    }
    goToPosition(ReadingPosition(block, offset), user: user);
  }

  void _goToCalculatedPage(int target, {required bool user}) {
    _cancelPending();
    layout.resume();
    // A new command may arrive before the frame that attaches the replaced PageController.
    // A ready page is shown at once and is not lost together with the cancelled wait.
    if (_pc == null || !_pc!.hasClients) {
      _cancelPageRequest();
      _onPageChanged(target, programmatic: !user);
      setState(_resetPages);
    } else {
      goToPage(target, user: user);
    }
  }

  /// A ready place keeps the page, a near one is computed up to, a far one is searched from the block start.
  void goToPosition(ReadingPosition place, {bool user = true}) {
    final shown = layout.findPage(place.block, place.offset, preferredPage: _page);
    final changingMetrics = _pendingLayout != null && _pendingMetrics != _shownMetrics;
    if (!user && !changingMetrics && shown != null) {
      _goToCalculatedPage(shown, user: user);
      return;
    }
    final direction = !user && !changingMetrics ? _nearbyDirection(place) : 0;
    if (direction != 0) {
      setState(() {
        _selectedBlock = null;
        _selectedAt = null;
        _waitOnLayout(place, user: user, backwards: direction < 0);
      });
      return;
    }
    setState(() {
      _cancelPageRequest();
      _selectedBlock = null;
      _selectedAt = null;
      if (user) _userMoved();
      if (identical(_pendingLayout, _layout)) _cancelPending();
      if (_pendingGoal?.block == place.block) {
        _pendingGoal = place;
        _pendingMove = true;
        _pendingUser = user;
        _onPendingLayout();
      } else if (_pendingLayout == null && layout.pages.first.firstBlock == place.block &&
          layout.pages.first.firstOffset == 0) {
        // This block is already being computed from its start: continue its queue without re-measuring the ready
        // prefix.
        _waitOnLayout(place, user: user);
        _onPendingLayout();
      } else {
        _startLayout(ReadingPosition(place.block, 0), retain: place, move: true, user: user);
      }
    });
  }

  int _nearbyDirection(ReadingPosition place, {ChapterPagination? source}) {
    final pagination = source ?? layout;
    final at = book.charsBefore(place.block) + place.offset;
    final first = pagination.pages.first;
    final last = pagination.pages.last;
    final chapter = book.chapterOf(place.block);
    final after = at - book.charsBefore(last.lastBlock) - last.lastEnd;
    if (!pagination.isComplete && chapter == last.chapter && after >= 0 && after <= _nearbyLayoutChars) return 1;
    final before = book.charsBefore(first.firstBlock) + first.firstOffset - at;
    if (pagination.hasPrevious && chapter == first.chapter && before > 0 && before <= _nearbyLayoutChars) return -1;
    return 0;
  }

  /// Until the target is ready, the previous page stays. A new command replaces the target of the same catch-up.
  void _waitOnLayout(ReadingPosition place, {required bool user, bool backwards = false}) {
    final continuing = identical(_pendingLayout, _layout);
    if (!continuing) {
      _cancelPending();
      _cancelPageRequest();
    }
    _pendingLayout = layout;
    _pendingGoal = place;
    _pendingMetrics = _shownMetrics;
    _pendingSave = true;
    _pendingMove = true;
    _pendingUser = user;
    layout.removeListener(_onPendingLayout);
    layout.removeListener(_onLayout);
    layout.addListener(_onLayout);
    layout.resume();
    if (backwards) {
      if (!layout.isLoadingPrevious) unawaited(layout.loadPrevious());
    } else {
      layout.cancelPrevious();
    }
    if (!continuing && _animatingTo != null) _resetPages();
  }

  BookPageLayout get _current => _layout!.pages[_page];

  ReadingPosition get _pagePosition => ReadingPosition(_current.firstBlock, _current.firstOffset);

  bool get _onLastPage => layout.endsBook(_current);

  /// The fraction of the book on screen; on the last page the book is finished — 100 % (FR-L4, rule d).
  double get _fraction => _onLastPage ? 1 : book.fractionAt(_current.firstBlock, _current.firstOffset);

  // --- paging -----------------------------------------------------------------------------------------

  /// A tap on the right or left third. A second tap during the animation of the first is not lost: the first transition
  /// is finished instantly, the second goes from it. A finger touch stops the scroll animation even before it is
  /// recognized as a tap, so the first transition's target is remembered during its whole animation.
  void _flip(int delta) {
    if (_reflowing) return;
    if (_pendingLayout != null) _cancelPending();
    final pc = _pc;
    if (pc == null) return;
    if (_grabbedAuto) {
      // The touch stopped the automatic page turn: this is the reader's choice, also at the edge of the book,
      // where an opposing turn stays on the same page.
      _grabbedAuto = false;
      _navOp++;
      _programmatic = false;
      _animatingTo = null;
      setState(_userMoved);
    }
    final pending = _flipTarget;
    final base = layout.isComplete ? math.min(pending ?? _page, layout.pages.length - 1) : pending ?? _page;
    final requested = layout.hasPrevious ? base + delta : math.max(0, base + delta);
    final target = layout.isComplete ? math.min(requested, layout.pages.length - 1) : requested;
    if (pc.hasClients && pending != null && pending >= 0 && pending < layout.pages.length &&
        (pc.page ?? _page.toDouble()) != pending) {
      _navOp++;
      _programmatic = false;
      _animatingTo = null;
      pc.jumpToPage(pending);
    }
    _flipTarget = target;
    _flipTimer?.cancel();
    goToPage(target).then((_) {
      if (mounted && _flipTarget == target) _flipTimer = Timer(_flipDuration, () => _flipTarget = null);
    });
  }

  static const _flipDuration = Duration(milliseconds: 320);
  int? _flipTarget;
  Timer? _flipTimer;

  Future<void> goToPage(int target, {bool user = true}) async {
    if (_reflowing) return;
    if (_pendingLayout != null) _cancelPending();
    final pc = _pc;
    if (pc == null) return;
    if (target >= 0) layout.cancelPrevious();
    if ((target >= layout.pages.length && !layout.isComplete) || (target < 0 && layout.hasPrevious)) {
      _navOp++;
      _waitingPage = target;
      _waitingUser = user;
      _waitingDone ??= Completer<void>();
      if (target < 0) unawaited(layout.loadPrevious());
      return _waitingDone!.future;
    }
    _waitingPage = null;
    _waitingDone?.complete();
    _waitingDone = null;
    target = target.clamp(0, layout.pages.length - 1);
    // Already paging there automatically — do not restart the animation (narration calls here on every step).
    if (target == _page || (!user && _programmatic && target == _animatingTo)) return;
    final op = ++_navOp;
    _programmatic = !user;
    if (!pc.hasClients) {
      _onPageChanged(target, programmatic: !user);
      setState(_resetPages);
      return;
    }
    final beyondExtent = target * pc.position.viewportDimension > pc.position.maxScrollExtent + 0.1;
    if ((target - _page).abs() == 1 && !beyondExtent) {
      _animatingTo = target;
      await pc.animateToPage(target, duration: _flipDuration, curve: Curves.easeOutCubic);
    } else {
      _onPageChanged(target, programmatic: !user);
      setState(_resetPages);
      return;
    }
    if (op != _navOp || !mounted) return; // another transition began — do not touch its flags
    _programmatic = false;
    _animatingTo = null;
    if (pc.hasClients && pc.page != null && pc.page!.round() != _page) {
      _onPageChanged(pc.page!.round(), programmatic: !user);
    }
  }

  /// A page change message from the [PageView] of generation [generation]: messages from an already replaced one (the
  /// layout was recomputed) mean nothing — neither paging by the user nor turning following off.
  void _onPageChangedFrom(int generation, int i) {
    if (generation != _generation) return;
    _onPageChanged(i);
  }

  void _onPageChanged(int i, {bool? programmatic}) {
    // A finger gesture is still going: what it did is decided when the page settles (_onScroll).
    final gesture = _dragStartPage != null;
    final auto = (programmatic ?? _programmatic) && !_userDragging;
    setState(() {
      _page = i;
      _anchor = _pagePosition;
      if (!auto && !gesture) _userMoved();
      // The paragraph selection is cleared on any page change — by gesture, tap, slider, table of contents, voice:
      // there is no such thing as an invisible selection (gesture review decision B).
      _selectedBlock = null;
      _selectedAt = null;
    });
    _reportShownPage();
    if (!auto && !gesture) _saveScreenPosition();
  }

  /// The user changed the page themselves. With this book's panel open — including in `stopped` — following
  /// is turned off: the place on screen is now chosen by the user (A§5, logic review item 1).
  void _userMoved() {
    if (_mine) {
      _following = false;
    }
  }

  /// "Finished" (FR-L4) is a separate fact: showing the last page sets it, showing a page earlier clears it.
  /// A re-layout (font, panel) does not clear it: that is not a move back.
  void _reportShownPage() {
    if (_onLastPage) {
      s.library.setFinished(book.id, true);
    } else if (_page < layout.pages.length - 1 || _current.lastBlock < book.blocks.length - 1 ||
        _current.lastEnd < book.blocks.last.text.length) {
      // The last known piece may turn out to be the end of the book; until the computation completes, do not clear
      // the flag already set by the narration controller.
      s.library.setFinished(book.id, false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (_reflowing) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      if (_pendingLayout != null) _cancelPending();
      // A finger on the page: the automatic transition is cancelled. Following turns off only if the gesture eventually
      // changes the page: a small drag with a return and a cancelled gesture change nothing.
      _userDragging = true;
      _dragStartPage ??= _page;
      _dragWaiting = false;
      _cancelPageRequest();
      _programmatic = false;
      _animatingTo = null;
    } else if (n is OverscrollNotification && n.dragDetails != null && !_dragWaiting &&
        ((n.overscroll > 0 && !layout.isComplete) || (n.overscroll < 0 && layout.hasPrevious))) {
      _edgeSide = n.overscroll > 0 ? 1 : -1;
      if (_pointerTravel.abs() > n.metrics.viewportDimension / 2) _requestEdgePage();
    } else if (n is ScrollEndNotification) {
      final start = _dragStartPage;
      final pc = _pc;
      final settled = pc != null && pc.hasClients && pc.page != null && (pc.page! - pc.page!.round()).abs() < 0.001;
      if (start != null && settled) {
        _dragStartPage = null;
        _userDragging = false;
        final grabbed = _grabbedAuto;
        _grabbedAuto = false;
        if (_page != start || grabbed) {
          setState(_userMoved);
          _saveScreenPosition();
        } else if (_following) {
          // A command may have arrived while a finger held the page. After the gesture returns, catch up with it, on a
          // pause too.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _dragStartPage == null && _following) _onNarration();
          });
        }
      } else if (start == null) {
        _userDragging = false;
      }
    }
    return false;
  }

  void _requestEdgePage() {
    if (_dragWaiting || _edgeSide == 0 || _pointerTravel.sign != -_edgeSide) return;
    final target = _pointerPage + _edgeSide;
    if (target >= 0 && target < layout.pages.length) return;
    _dragWaiting = true;
    _waitingPage = target;
    _waitingUser = true;
    if (target < 0) unawaited(layout.loadPrevious());
  }

  void _endPagePointer(PointerUpEvent event) {
    _edgeVelocity?.addPosition(event.timeStamp, event.position);
    final velocity = _edgeVelocity?.getVelocity().pixelsPerSecond.dx ?? 0;
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    // At the edge there is no page yet for the ordinary PageView physics. Apply the same fling thresholds;
    // a small drag with a return and a stop does not become a "back" command.
    final physics = pc.position.physics;
    if (_pointerTravel.abs() >= physics.minFlingDistance && velocity.abs() >= physics.minFlingVelocity &&
        velocity.sign == -_edgeSide) {
      _requestEdgePage();
    }
  }

  /// The screen writes the position only while listening is not active (A§5).
  void _saveScreenPosition() {
    if (narration.bookId == book.id && narration.isActive) return;
    s.library.savePosition(book.id, _pagePosition, fraction: _fraction);
  }

  // --- following the voice (A§5, FR-P4) ---------------------------------------------------------------

  /// The place that is voiced now in this book — as the controller reports it.
  ReadingPosition? get soundingPosition {
    if (narration.bookId != book.id) return null;
    return narration.sounding;
  }

  void _onNarration() {
    if (!mounted) return;
    final state = narration.state;
    final previousAt = _lastSounding;
    final at = soundingPosition;
    _lastSounding = at;
    // An explicit user command — wherever it comes from (screen, notification, headset) — turns following on
    // (A§5, logic review item 5). Automatic transitions do not change the counter.
    final command = narration.commandRevision != _seenCommands;
    if (command) {
      _seenCommands = narration.commandRevision;
      if (narration.bookId == book.id) {
        _following = true;
        // An explicit audio command cancels the previous paging, even if the voice stayed
        // on the current page: the completion of that animation is no longer the reader's choice.
        // While a finger holds the page, its gesture keeps priority (A§5).
        if (_dragStartPage == null) {
          _cancelPageRequest();
          if (_pc != null && _animatingTo != null) _resetPages();
        }
      }
    }
    if (narration.bookId == book.id) {
      if (state == NarrationState.stopped && _lastState != NarrationState.stopped) _following = true;
      // While a paragraph is selected for "Read from here", the page under the finger does not follow the voice (path
      // review item 8): otherwise the button disappears before it can be pressed. Once the selection is cleared, the
      // screen catches up with the voice.
      final choosing = _selectedBlock != null;
      // An unfinished manual touch also has priority over the next audio event.
      final gesture = _dragStartPage != null || (_waitingPage != null && _waitingUser) ||
          (_animatingTo != null && !_programmatic);
      // The voice advanced into the page that the reader flipped forward. A plain event or a height change
      // does not do that: the previous place must be outside the same page.
      if (!_following && !choosing && !gesture && _pendingLayout == null && _layout != null &&
          state == NarrationState.playing && at != null && previousAt != null &&
          (at.block > previousAt.block || (at.block == previousAt.block && at.offset > previousAt.offset)) &&
          !_current.contains(previousAt.block, previousAt.offset) && _current.contains(at.block, at.offset)) {
        _following = true;
      }
      if (!choosing && !gesture && _following && at != null && _layout != null &&
          state != NarrationState.idle) {
        if (command && !_current.contains(at.block, at.offset)) {
          goToPosition(at, user: false);
        } else {
          _goToPlace(at.block, at.offset, user: false);
        }
      }
    }
    _lastState = state;
    setState(() {});
  }

  void _backToReadingPlace() {
    setState(() {
      _following = true;
      _cancelPageRequest();
      if (_animatingTo != null) _resetPages();
    });
    final at = soundingPosition;
    if (at != null) {
      if (_current.contains(at.block, at.offset)) {
        _goToPlace(at.block, at.offset, user: false);
      } else {
        goToPosition(at, user: false);
      }
    }
  }

  // --- gestures ---------------------------------------------------------------------------------------

  void _clearSelection() {
    setState(() {
      _selectedBlock = null;
      _selectedAt = null;
    });
    _onNarration();
  }

  void _onTapUp(TapUpDetails d, Size area) {
    if (_selectedBlock != null) {
      _clearSelection();
      return;
    }
    // A footnote mark outranks the panels: a visible link is opened with the panels open too (review item 12).
    final local = d.localPosition - Offset(_pad.left, _pad.top);
    final hit = hitTestPage(book: book, page: _current, style: _style, columnWidth: _column.width, p: local);
    if (hit.noteId != null) {
      _afterLayer(showNoteSheet(context, book: book, noteId: hit.noteId!, style: _style));
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
    final frag = _current.fragments.firstWhere((f) => f.block == b);
    setState(() {
      _selectedBlock = b;
      _selectedAt = ReadingPosition(b, frag.start);
    });
  }

  void _setPanels(bool v) {
    setState(() => _panels = v);
    setImmersive(!v);
  }

  // --- actions ----------------------------------------------------------------------------------------

  /// A transition to another screen: the status bar is needed there, immersive mode — only in reading.
  Future<T?> _push<T>(Widget screen) async {
    setImmersive(false);
    final result = await _afterLayer(Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen)));
    if (mounted) setImmersive(!_panels);
    return result;
  }

  bool _requireKey() {
    if (s.settings.hasApiKey) return true;
    // No key: "Listen" leads to the settings, to the key field (FR-P7).
    _push<void>(SettingsScreen(services: s, focusKey: true));
    return false;
  }

  /// "Listen" (FR-P3): the screen only reports the visible page, the controller chooses the place. Following is turned
  /// on at once: the "To reading place" button cannot exist after the start.
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
      _selectedAt = null;
    });
    narration.readFrom(book, block);
  }

  // "Listen" from a pause and from the error panel, "back", "forward" — controller commands; following is turned on by
  // its counter of explicit commands (_onNarration), the same for the screen, the notification and the headset (rule a,
  // A§5).
  void _play() => narration.resume();
  void _previous() => narration.previous();
  void _next() => narration.next();

  void _closeNarration() {
    // "Close" is one controller command: the session ends, then the reading position — the place on screen — is handed
    // to the writer (FR-P8). The panel goes away, the page becomes longer and is recomputed so that this place
    // stays on screen: if the screen was following the voice — the voiced place, otherwise — the start of the page that
    // the user flipped to themselves. Previously the page start was taken, and the recomputation took the screen back
    // to where the voiced paragraph no longer was (owner's remark 2026-11-14). "Finished" is a separate fact and is not
    // changed here.
    final place = (_following ? soundingPosition : null) ?? _pagePosition;
    _anchor = place;
    _heldAfterClose = place;
    narration.close(screenPosition: place);
    setState(() => _following = true);
  }

  Future<void> _openContents() async {
    final chapter = await _push<int>(TocScreen(services: s, book: book, current: _current.chapter));
    if (chapter == null || !mounted) return;
    // The new _Slide are hidden at once: the pop result arrives before the first return frame.
    _panelsVersion++;
    _setPanels(false);
    final listening = narration.bookId == book.id &&
        (narration.isActive || narration.state == NarrationState.paused);
    if (listening) {
      // During listening, choosing a chapter is a new audio place: the voice goes to the chapter start (the current one
      // too), following is turned on by a controller command, the voice drives the page — the transition is not manual
      // paging (path review item 1, a).
      final block = book.chapters[chapter].firstBlock;
      if (layout.findPage(block, 0) == null) {
        // The table of contents explicitly chooses a new start, not a continuation of a nearby stretch.
        setState(() => _startLayout(ReadingPosition(block, 0), move: true));
      }
      narration.moveIfListening(book, block);
    } else {
      _goToPlace(book.chapters[chapter].firstBlock, 0);
    }
  }

  /// A key rejection: "Change key" leads to the key field in settings; "Back" returns to the book (FR-P7).
  Future<void> _changeKey() => _push<void>(SettingsScreen(services: s, focusKey: true));

  Future<void> _openVoice() => _push<void>(VoiceScreen(services: s, book: book));

  // --- building ---------------------------------------------------------------------------------------

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
    // A layer change under the finger — the reading bottom panel ↔ the player panel, the player panel view (controls,
    // error, end of book), the download row — protection against a follow-up touch (gesture review decision A, A§8.1).
    // Showing and hiding the reading panels by a tap in the center is not counted as a layer under the finger: they
    // appear at the edges, not under the finger.
    final playerKind = !_mine
        ? 'none'
        : narration.state != NarrationState.stopped
            ? 'controls'
            : narration.stopReason == StopReason.error
                ? 'error'
                : 'end';
    final signature = (playerKind, downloading);
    if (signature != _layerSignature) {
      _layerSignature = signature;
      _messageBody = null;
      _guardLayer();
    }
    // The system "Back" (gesture review decision J, A§8.1): 1) clear the paragraph selection; 2) a sheet, dialog or
    // footnote is closed by the navigator — they are their own routes; 3) the reading panels are hidden — show them,
    // the book is not closed; 4) the panels are shown — close the book. The Android edge gesture is "Back": an
    // accidental swipe from the edge in immersive reading only shows the panels. The "Back" arrow in the header closes
    // the book at once.
    return PopScope(
      canPop: _selectedBlock == null && _panels,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedBlock != null) {
          _clearSelection();
        } else if (!_panels) {
          _setPanels(true);
        }
      },
      child: AbsorbPointer(
        absorbing: _guarded,
        child: _scaffold(context, downloadLine, downloading: downloading),
      ),
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
        // The page ends above everything that is permanently occupied at the bottom: the player panel (together with
        // its download row and "To reading place") or the download row and the book fraction.
        final reserved = playerVisible
            ? ((narration.state == NarrationState.stopped || downloading ? _messageBody : null) ??
                PlayerPanel.controlsHeight + _bottomInset) + 16
            : _bottomInset + (downloading ? 104 : 44);
        _pad = EdgeInsets.fromLTRB(24, _topInset + 28, 24, reserved);
        _column = Size(area.width - _pad.horizontal, math.max(_style.lineHeight * 3, area.height - _pad.vertical));
        _wantedMetrics = (style: _style, column: _column, pad: _pad);
        _ensureLayout(_style, _column);
        if (_pendingLayout != null) {
          _style = _shownMetrics!.style;
          _column = _shownMetrics!.column;
          _pad = _shownMetrics!.pad;
        }
        final generation = _generation;
        final highlight = <int>{
          if (playerVisible && narration.block != null) narration.block!,
          ?_selectedBlock,
        };
        final previewChapter = _sliderDrag == null ? _current.chapter : book.chapterOf(book.placeAt(_sliderDrag!).$1);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                // A finger landed on the page in the middle of an automatic page turn after the voice — grabbed it
                // (decision C). Checked at the moment of the touch: by the start of the drag the turn is already
                // stopped.
                onPointerDown: (event) {
                  _grabbedAuto = _programmatic && _animatingTo != null;
                  _edgeVelocity = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.position);
                  _pointerStartX = event.position.dx;
                  _pointerTravel = 0;
                  _pointerPage = _page;
                  _edgeSide = 0;
                  _dragWaiting = false;
                },
                onPointerMove: (event) {
                  _pointerTravel = event.position.dx - _pointerStartX;
                  _edgeVelocity?.addPosition(event.timeStamp, event.position);
                },
                onPointerUp: _endPagePointer,
                onPointerCancel: (_) => _edgeSide = 0,
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
                    // Even the single ready page accepts a gesture toward a not-yet-computed edge.
                    physics: !_reflowing
                        ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => _onPageChangedFrom(generation, i),
                    itemCount: _layout!.pages.length,
                    // A predominantly vertical gesture (angle to the horizontal over 45° at the moment of recognition)
                    // does not page and does nothing (decision D, FR-R2). The recognizer sits inside the page, deeper
                    // than the paging recognizer, and sees every finger movement first: it takes the gesture when the
                    // finger has gone up or down beyond the threshold and farther than sideways.
                    itemBuilder: (context, i) => RawGestureDetector(
                      gestures: {
                        MostlyVerticalDragRecognizer: GestureRecognizerFactoryWithHandlers<MostlyVerticalDragRecognizer>(
                          MostlyVerticalDragRecognizer.new,
                          (r) => r
                            ..onStart = (_) {}
                            ..onUpdate = (_) {}
                            ..onEnd = (_) {},
                        ),
                      },
                      child: ColoredBox(
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
                    child: Text(shelfProgress(l10n, _fraction),
                        key: const Key('footer-percent'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ]),
              ),
            if (_selectedBlock != null) _readFromHere(context, area),
            _Slide(
              key: ValueKey('top-$_panelsVersion'),
              visible: _panels,
              from: const Offset(0, -1),
              alignment: Alignment.topCenter,
              child: _TopBar(
                title: book.title,
                subtitle: chapterLabel(book, previewChapter),
                chapterExcerpt: book.chapters[previewChapter].title.trim().isEmpty,
                // The "Back" arrow in the header closes the book at once; the system "Back" — in the order of decision
                // J.
                onBack: () => Navigator.of(context).pop(),
                onContents: _openContents,
                onAppearance: () => _afterLayer(showTextAppearanceSheet(context, s.settings, s.themePreviews)),
                onTitleLongPress: s.openDemoStates == null ? null : () => s.openDemoStates!(context),
              ),
            ),
            if (!playerVisible)
              _Slide(
                key: ValueKey('bottom-$_panelsVersion'),
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
                  onSpeed: () => _afterLayer(showSpeedSheet(context, s.settings, narration)),
                  onSleep: () => _afterLayer(showSleepSheet(context, narration)),
                  onTopUp: () => s.openUrl(context, billingUrl),
                  onChooseModel: () => _push<void>(SettingsScreen(services: s, openModel: true)),
                  onChangeKey: _changeKey,
                  onPlay: _play,
                  onPrevious: _previous,
                  onNext: _next,
                  header: _panels ? _sliderStrip(context) : null,
                  download: downloadLine,
                  bottomInset: _bottomInset,
                  onMessageHeight: (h) {
                    if (_messageBody == null || (h - _messageBody!).abs() > 0.5) setState(() => _messageBody = h);
                  },
                ),
              ),
          ],
        );
      }),
    );
  }

  /// The book slider and the fraction. The chapter title is only in the header; while dragging, the header shows the
  /// chapter that the finger will land in.
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
            child: Text(context.l10n.ofBook(progressForDisplay(value)),
                textAlign: TextAlign.end, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface)),
          ),
          Slider(
            key: const Key('book-slider'),
            value: value.clamp(0.0, 1.0),
            // The 2024 Material 3 look; the flag is marked deprecated, but there is no other way to turn it on.
            // ignore: deprecated_member_use
            year2023: false,
            onChanged: (v) => setState(() => _sliderDrag = v),
            onChangeEnd: (v) {
              final (b, o) = book.placeAt(v);
              final target = _layout!.findPage(b, o, preferredPage: _page);
              // The slider is released on another page — a manual move, following is turned off. A tap without
              // a shift (the same page) changes nothing (decision H, FR-P4, FR-R5).
              setState(() {
                _sliderDrag = null;
                if (target != _page) _userMoved();
              });
              _goToPlace(b, o);
            },
          ),
        ],
      ),
    );
  }

  /// "Read from here" — at the paragraph, but always in the visible part of the screen: not past its edge and not under
  /// the player panel.
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

/// Smooth appearance of the panel: shift + opacity; a hidden panel does not catch touches.
class _Slide extends StatelessWidget {
  const _Slide({super.key, required this.visible, required this.from, required this.alignment, required this.child});

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
    required this.chapterExcerpt,
    required this.onBack,
    required this.onContents,
    required this.onAppearance,
    this.onTitleLongPress,
  });

  final String title;
  final String? subtitle;
  final bool chapterExcerpt;
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
          // 8 dp at the side: the 48 × 48 areas of the outermost buttons do not reach into the rounding of the header's
          // lower corners (a touch at the corner of "Back" is not cut off, gesture review 2026-11-14).
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
                        // The chapter title — at most two lines; the start of an unnamed one — one line.
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(subtitle!,
                              key: const Key('top-bar-chapter'),
                              maxLines: chapterExcerpt ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
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
                  // The book's voice — also before the first listening (FR-V2).
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

/// A vertical recognizer that takes only a predominantly vertical gesture: the finger went up or
/// down beyond the touch threshold and farther than sideways (angle to the horizontal over 45°). Then the page paging
/// arena loses and the gesture does nothing (gesture review decision D, FR-R2). A predominantly horizontal gesture it
/// does not touch — paging takes it.
class MostlyVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  MostlyVerticalDragRecognizer({super.debugOwner});

  final Map<int, Offset> _origin = {};
  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _origin[event.pointer] = event.position;
    _moved = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final origin = _origin[event.pointer];
    if (origin != null && event is PointerMoveEvent) _moved = event.position - origin;
    if (event is PointerUpEvent || event is PointerCancelEvent) _origin.remove(event.pointer);
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      super.hasSufficientGlobalDistanceToAccept(pointerDeviceKind, deviceTouchSlop) && _moved.dy.abs() > _moved.dx.abs();
}

/// While "Download chapter" runs — a short row with the ready fraction and "Stop" (owner's decision 2026-11-14, FR-D2).
/// Always visible: in the page footer, in the bottom panel and in the player panel.
class DownloadLine extends StatelessWidget {
  const DownloadLine({super.key, required this.task, required this.onStop});

  final ChapterDownloadTask task;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The row's shape is only painted (ShapeDecoration) and does not clip touches: with a Material of rounded shape
    // hit testing follows the shape, and the corners of the "Stop" 48 × 48 area were cut off (gesture review decision
    // I, FR-R8).
    return DecoratedBox(
      key: const Key('download-strip'),
      decoration: ShapeDecoration(color: scheme.surfaceContainerHigh, shape: const StadiumBorder()),
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
