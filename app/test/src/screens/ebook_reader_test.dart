import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/reader_harness.dart';

void main() {
  late FakeApi api;
  late ReaderHarness reader;

  setUp(() async {
    api = FakeApi()..files.addAll(ebookFiles());
    final ebook = (await api.syncEbook(ebookIsbn, ebookState().book!.ebook!))!;
    reader = ReaderHarness(api, ebook, DateTime.utc(2026, 10, 23, 18));
  });

  EbookMap map() => reader.ebook.map;

  ReadingStart startAgo(Duration ago, {String id = 'kept0123'}) => ReadingStart(
    id: id,
    isbn: ebookIsbn,
    offset: map().offsetAt(15),
    startedAt: reader.now.subtract(ago),
    textSha: map().textSha,
  );

  testWidgets('the screen is the book text only', (tester) async {
    await reader.open(tester, latestPage: 20);
    expect(find.byType(EbookReaderScreen), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Zbrodnia i kara'), findsNothing);
    expect(find.textContaining('≈ p.'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('opening starts a session where the position loaded', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    final start = await api.readingStart(ebookIsbn);
    expect(start, isNotNull);
    expect(map().pageAt(start!.offset), 20);
    expect(start.offset, greaterThan(0));
    expect(start.startedAt, reader.now);
    expect(start.textSha, map().textSha);
  });

  testWidgets('a start from within 6 h is kept (app killed and back)', (
    tester,
  ) async {
    await api.startReading(startAgo(const Duration(hours: 2)));
    await reader.open(tester, latestPage: 20);
    expect((await api.readingStart(ebookIsbn))!.id, 'kept0123');
  });

  testWidgets('a start over 6 h old is dropped for a fresh one', (
    tester,
  ) async {
    await api.startReading(startAgo(const Duration(hours: 7)));
    await reader.open(tester, latestPage: 20);
    final start = (await api.readingStart(ebookIsbn))!;
    expect(start.id, isNot('kept0123'));
    expect(start.startedAt, reader.now);
    expect(map().pageAt(start.offset), 20);
  });

  testWidgets('a right-to-left swipe stops the session at the position', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    await reader.forward(tester, 4);
    final at = reader.shown(tester);
    reader.now = reader.now.add(const Duration(hours: 1));
    await reader.swipeOut(tester);
    expect(reader.closed, isTrue);
    final done = reader.closedWith!;
    expect(done.startPage, 20);
    expect(done.endPage, map().pageAt(at));
    expect(done.endPage, greaterThan(20));
    expect(await api.readingPosition(ebookIsbn), at);
    expect(await api.readingStart(ebookIsbn), isNull);
    expect((await api.appSessions()).single.endPage, done.endPage);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('less than a page is dropped without a word', (tester) async {
    await reader.open(tester, latestPage: 20);
    reader.now = reader.now.add(const Duration(minutes: 5));
    await reader.swipeOut(tester);
    expect(reader.closed, isTrue);
    expect(reader.closedWith, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(await api.readingStart(ebookIsbn), isNull);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('over 6 h since the start is dropped silently', (tester) async {
    await reader.open(tester, latestPage: 20);
    await reader.forward(tester, 4);
    reader.now = reader.now.add(const Duration(hours: 7));
    await reader.swipeOut(tester);
    expect(reader.closedWith, isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(await api.readingStart(ebookIsbn), isNull);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('flipping through is not saved, and says so', (tester) async {
    await reader.open(tester, latestPage: 20);
    await reader.forward(tester, 4);
    reader.now = reader.now.add(const Duration(minutes: 1));
    await reader.swipeOut(tester);
    expect(reader.closedWith, isNull);
    expect(find.text('Too fast to count - not saved'), findsOneWidget);
    expect(await api.readingStart(ebookIsbn), isNull);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('system back goes through the same stop', (tester) async {
    await reader.open(tester, latestPage: 20);
    await reader.forward(tester, 4);
    reader.now = reader.now.add(const Duration(hours: 1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(reader.closedWith, isNotNull);
    expect(await api.readingStart(ebookIsbn), isNull);
  });

  testWidgets('Escape goes through the same stop', (tester) async {
    await reader.open(tester, latestPage: 20);
    await reader.forward(tester, 4);
    reader.now = reader.now.add(const Duration(hours: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(reader.closedWith, isNotNull);
  });

  testWidgets('starting here names the paper start photo it closed', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20, paperStart: 18);
    expect(find.textContaining('start photo of p. 18'), findsOneWidget);
  });

  testWidgets('a kept session does not re-announce the paper photo', (
    tester,
  ) async {
    await api.startReading(startAgo(const Duration(hours: 1)));
    await reader.open(tester, latestPage: 20, paperStart: 18);
    expect(find.textContaining('start photo of p. 18'), findsNothing);
  });

  testWidgets('immersive while reading, edge to edge after', (tester) async {
    final modes = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await reader.open(tester, latestPage: 20);
    expect(modes, [SystemUiMode.immersiveSticky.toString()]);
    await reader.swipeOut(tester);
    expect(modes.last, SystemUiMode.edgeToEdge.toString());
  });

  testWidgets('the font size saved in settings is the one used', (
    tester,
  ) async {
    await api.saveFontSize(26);
    await reader.open(tester, latestPage: 20);
    expect(reader.scroll(tester).widget.fontSize, 26);
  });

  testWidgets('no saved size: 18 on a phone', (tester) async {
    await reader.open(tester, latestPage: 20);
    expect(reader.scroll(tester).widget.fontSize, 18);
  });
}
