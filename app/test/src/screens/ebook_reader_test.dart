import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';

void main() {
  late FakeApi api;
  late Ebook ebook;
  late DateTime now;
  AppSession? closedWith;

  setUp(() async {
    api = FakeApi()..files.addAll(ebookFiles());
    ebook = (await api.syncEbook(ebookIsbn, ebookState().book!.ebook!))!;
    now = DateTime.utc(2026, 10, 23, 18);
    closedWith = null;
  });

  Future<void> open(
    WidgetTester tester, {
    int? latestPage,
    int? paperStart,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  closedWith = await Navigator.of(context).push<AppSession>(
                    MaterialPageRoute(
                      builder: (_) => EbookReaderScreen(
                        api: api,
                        ebook: ebook,
                        title: 'Zbrodnia i kara',
                        latestPage: latestPage,
                        paperStart: paperStart,
                        clock: () => now,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
    }
  }

  int pageShown(WidgetTester tester) {
    final label = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.startsWith('≈ p. '));
    return int.parse(label.substring(5).split(' ').first);
  }

  group('pages', () {
    test('screens start at paragraphs and cover the whole text', () {
      final starts = screenStarts(ebookText, 2000);
      expect(starts.first, 0);
      for (final s in starts.skip(1)) {
        expect(ebookText.substring(s - 2, s), '\n\n');
      }
      for (var i = 1; i < starts.length - 1; i++) {
        expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(2000));
      }
    });

    test('a paragraph longer than two screens is cut at a space', () {
      final text = 'word ' * 2000;
      final starts = screenStarts(text, 1000);
      expect(starts.length, greaterThan(5));
      for (final s in starts.skip(1)) {
        expect(text[s - 1], ' ');
      }
      expect(screenStarts('', 1000), [0]);
    });
  });

  testWidgets('opens where the paper reading stopped', (tester) async {
    await open(tester, latestPage: 20);
    expect(pageShown(tester), 20);
  });

  testWidgets('a position further on wins over the paper page', (tester) async {
    await api.savePosition(ebookIsbn, ebook.map.offsetAt(30));
    await open(tester, latestPage: 20);
    expect(pageShown(tester), inInclusiveRange(27, 30)); // its screen
  });

  testWidgets('a session runs from the Start tap to the Stop tap', (
    tester,
  ) async {
    await open(tester, latestPage: 20);
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    final start = await api.readingStart(ebookIsbn);
    expect(ebook.map.pageAt(start!.offset), 20);
    expect(start.startedAt, now);
    expect(find.textContaining('Reading since'), findsOneWidget);
    await next(tester, 3);
    now = now.add(const Duration(hours: 1));
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    expect(closedWith, isNotNull);
    expect(closedWith!.startPage, 20);
    expect(closedWith!.endPage, greaterThan(24));
    expect(await api.readingStart(ebookIsbn), isNull);
    expect((await api.appSessions()).single.key, start.id);
    expect(await api.store.list('outbox/'), isNotEmpty);
  });

  testWidgets('the position and the session survive closing the reader', (
    tester,
  ) async {
    await open(tester, latestPage: 20);
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    await next(tester, 2);
    final there = pageShown(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await open(tester);
    expect(pageShown(tester), there);
    expect(find.text('Stop reading'), findsOneWidget);
  });

  testWidgets('less than a page asks to keep reading or discard', (
    tester,
  ) async {
    await open(tester, latestPage: 20);
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Less than a page'), findsOneWidget);
    await tester.tap(find.text('Keep reading'));
    await tester.pumpAndSettle();
    expect(await api.readingStart(ebookIsbn), isNotNull);
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await api.readingStart(ebookIsbn), isNull);
    expect(find.text('Start reading here'), findsOneWidget);
  });

  testWidgets('a start over 6 h old cannot count', (tester) async {
    await open(tester, latestPage: 20);
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    await next(tester, 2);
    now = now.add(const Duration(hours: 7));
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('more than 6 h ago'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await api.readingStart(ebookIsbn), isNull);
    expect(await api.appSessions(), isEmpty);
  });

  testWidgets('flipping through warns before it stops', (tester) async {
    await open(tester, latestPage: 20);
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    await next(tester, 3);
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('under 50 s a page'), findsOneWidget);
    await tester.tap(find.text('Keep reading'));
    await tester.pumpAndSettle();
    expect(closedWith, isNull);
    await tester.tap(find.text('Stop reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop anyway'));
    await tester.pumpAndSettle();
    expect(closedWith, isNotNull);
  });

  testWidgets('an open paper start photo is named, not a block', (
    tester,
  ) async {
    await open(tester, latestPage: 20, paperStart: 18);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start reading here'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('start photo of p. 18'), findsOneWidget);
  });

  testWidgets('the font size changes and is kept', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(await api.fontSize(), EbookStore.defaultFontSize + 2);
    await tester.tap(find.byTooltip('Smaller text'));
    await tester.tap(find.byTooltip('Smaller text'));
    await tester.pumpAndSettle();
    expect(await api.fontSize(), EbookStore.defaultFontSize - 2);
  });

  testWidgets('previous goes back a screen', (tester) async {
    await open(tester, latestPage: 20);
    final first = pageShown(tester);
    await next(tester, 2);
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(pageShown(tester), first);
  });
}
