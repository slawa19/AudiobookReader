// Помощники проверки жестов (test/gesture_*.dart): палец водится настоящими событиями указателя с метками
// времени, чтобы распознаватели видели скорость, как на телефоне. Существующие помощники не меняются.

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/reader/pagination.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

const pageAreaKey = Key('page-area');

Rect pageRect(WidgetTester tester) => tester.getRect(find.byKey(pageAreaKey));

/// Палец с часами: каждое событие несёт своё время — иначе скорость жеста для распознавателя равна нулю.
class Finger {
  Finger._(this.tester, this.gesture);

  final WidgetTester tester;
  final TestGesture gesture;
  Duration _t = Duration.zero;

  static Future<Finger> down(WidgetTester tester, Offset at, {int pointer = 1}) async {
    final g = await tester.startGesture(at, pointer: pointer);
    return Finger._(tester, g);
  }

  /// Сдвиг на [delta] за [ms] миллисекунд шагами по ~16 мс; кадры идут вместе с пальцем.
  Future<void> move(Offset delta, {int ms = 160}) async {
    final steps = (ms / 16).ceil().clamp(1, 1000);
    for (var i = 0; i < steps; i++) {
      _t += Duration(milliseconds: (ms / steps).round());
      await gesture.moveBy(delta / steps.toDouble(), timeStamp: _t);
      await tester.pump(Duration(milliseconds: (ms / steps).round()));
    }
  }

  /// Палец стоит на месте [ms] миллисекунд.
  Future<void> hold(int ms) async {
    _t += Duration(milliseconds: ms);
    var left = ms;
    while (left > 0) {
      final step = left > 50 ? 50 : left;
      await tester.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> up() async {
    await gesture.up(timeStamp: _t);
    await tester.pump();
  }

  Future<void> cancel() async {
    await gesture.cancel(timeStamp: _t);
    await tester.pump();
  }
}

/// Смахивание: вниз в [from], сдвиг на [delta] за [ms] мс, вверх. Кадры не «усаживаются» — это делает тест.
Future<void> swipe(WidgetTester tester, Offset from, Offset delta, {int ms = 160}) async {
  final f = await Finger.down(tester, from);
  await f.move(delta, ms: ms);
  await f.up();
}

/// Быстрое касание без ожидания: вниз, 40 мс, вверх, один кадр.
Future<void> quickTap(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 40));
  await g.up();
  await tester.pump();
}

/// Время идёт кадрами по 16 мс — анимации и таймеры отрабатывают, как на экране.
Future<void> frames(WidgetTester tester, int ms) async {
  var left = ms;
  while (left > 0) {
    await tester.pump(const Duration(milliseconds: 16));
    left -= 16;
  }
}

BookPageLayout currentPage(WidgetTester tester) {
  final st = reader(tester);
  return st.layout.pages[st.page];
}

/// Знаки сносок на странице [page] (по умолчанию — текущей), по порядку.
List<String> notesOnPage(WidgetTester tester, [int? page]) {
  final st = reader(tester);
  final book = st.widget.book;
  final pg = st.layout.pages[page ?? st.page];
  return [
    for (final f in pg.fragments)
      for (final s in book.blocks[f.block].spans)
        if (s.style == SpanStyle.noteRef && s.start >= f.start && s.end <= f.end) s.noteId!,
  ];
}

bool pageHasNotes(WidgetTester tester, [int? page]) => notesOnPage(tester, page).isNotEmpty;

/// Подготовка (не жест): встать на страницу [page]. Переход на соседнюю страницу анимирован, поэтому его
/// завершения ждут кадрами, а не `await`.
Future<void> jumpTo(WidgetTester tester, int page) async {
  final done = reader(tester).goToPage(page);
  await tester.pumpAndSettle();
  await done;
}

/// Подготовка (не жест): встать на первую страницу не раньше [from], для которой верно [test].
Future<int> gotoPageWhere(WidgetTester tester, bool Function(int page) test, {int from = 0}) async {
  final st = reader(tester);
  for (var i = from; i < st.layout.pages.length; i++) {
    if (test(i)) {
      await jumpTo(tester, i);
      return i;
    }
  }
  throw StateError('подходящей страницы нет');
}

/// Страница из одних целых абзацев в середине главы, без сносок и картинок, не первая и не последняя.
Future<int> gotoPlainPage(WidgetTester tester, {int from = 3}) {
  final st = reader(tester);
  final book = st.widget.book;
  bool plain(int i) {
    if (i <= 0 || i >= st.layout.pages.length - 2) return false;
    for (final j in [i - 1, i, i + 1, i + 2]) {
      final pg = st.layout.pages[j];
      if (pageHasNotes(tester, j)) return false;
      if (pg.fragments.any((f) => book.blocks[f.block].kind != BlockKind.paragraph)) return false;
      if (pg.chapter != st.layout.pages[i].chapter) return false;
    }
    return true;
  }

  return gotoPageWhere(tester, plain, from: from);
}

/// Точка экрана по долям области страницы.
Offset at(WidgetTester tester, double fx, double fy) {
  final r = pageRect(tester);
  return Offset(r.left + r.width * fx, r.top + r.height * fy);
}

/// «Слушать» из нижней панели одним касанием и время на «Готовлю голос…».
Future<void> startListening(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('listen')));
  await advance(tester, const Duration(seconds: 2));
}

/// Открывает экран чтения для произвольной (синтетической) книги поверх полки.
Future<void> openSynthetic(WidgetTester tester, Prototype p, Book book) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(services: p.services, book: book)));
  await tester.pumpAndSettle();
}
