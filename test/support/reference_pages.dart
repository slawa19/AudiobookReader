// Снимки фиксируют конкретные страницы прототипа. Их начальные позиции получаем тем же порционным
// модулем, начиная с главы; это подготовка образца в тесте, а не режим работы приложения.
import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flows.dart' as flows;
import 'harness.dart';
import 'pagination.dart';

final _origins = Expando<ReadingPosition>();

Future<void> alignReferencePage(WidgetTester tester) async {
  if (find.byType(ReaderScreen).evaluate().isEmpty) return;
  final st = reader(tester);
  final page = st.layout.pages[st.page];
  final at = st.following ? st.soundingPosition : null;
  final narration = st.widget.services.narration;
  final mine = narration.bookId == st.widget.book.id && narration.state != NarrationState.idle;
  final origin = mine ? null : _origins[st];
  final block = at?.block ?? origin?.block ?? page.firstBlock;
  final offset = at?.offset ?? origin?.offset ?? page.firstOffset;
  final reference = await paginate(tester: tester, book: st.widget.book, style: st.pageStyle,
      column: st.columnSize, imageSizes: st.widget.services.library.imageSizes(st.widget.book.id));
  final target = reference.pages[reference.pageOf(block, offset)];
  reference.dispose();
  if (page.firstBlock == target.firstBlock && page.firstOffset == target.firstOffset) return;
  st.goToPosition(ReadingPosition(target.firstBlock, target.firstOffset), user: false);
  await tester.pump();
  await tester.pump();
}

Future<void> openKapitanskaya(WidgetTester tester, Prototype p, {ReadingPosition? at}) async {
  await flows.openKapitanskaya(tester, p, at: at);
  final page = reader(tester).layout.pages[reader(tester).page];
  _origins[reader(tester)] = ReadingPosition(page.firstBlock, page.firstOffset);
  await alignReferencePage(tester);
}

Future<void> openDama(WidgetTester tester, Prototype p, {ReadingPosition? at}) async {
  await flows.openDama(tester, p, at: at);
  final page = reader(tester).layout.pages[reader(tester).page];
  _origins[reader(tester)] = ReadingPosition(page.firstBlock, page.firstOffset);
  await alignReferencePage(tester);
}
