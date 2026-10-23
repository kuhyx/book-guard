import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/ebook_pages.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';

/// Words of uneven length, so lines wrap at different places.
String _words(int n, int seed) =>
    [for (var i = 0; i < n; i++) 'w${seed}_$i${'x' * ((i * 7 + seed) % 9)}']
        .join(' ');

/// Short paragraphs around one far longer than any screen.
final String _book = [
  _words(40, 1),
  _words(30, 2),
  _words(900, 3),
  _words(25, 4),
  _words(300, 5),
  _words(12, 6),
].join('\n\n');

String _squash(String s) => s.trim().split(RegExp(r'\s+')).join(' ');

void main() {
  late FakeApi api;
  late Ebook ebook;

  setUp(() {
    api = FakeApi();
    ebook = Ebook(EbookMap.fromJson(ebookMapJson(text: _book))!, _book);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(640, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: EbookReaderScreen(api: api, ebook: ebook, title: 'Book'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The screen's text, after checking every line of it is inside the
  /// screen: nothing is cut off below, nothing scrolls inside it.
  String shown(WidgetTester tester) {
    final screen = tester.getRect(find.byType(EbookScreenText));
    final texts = find.descendant(
      of: find.byType(EbookScreenText),
      matching: find.byType(Text),
    );
    final parts = <String>[];
    for (final element in texts.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(
        rect.bottom,
        lessThanOrEqualTo(screen.bottom + 0.01),
        reason: 'text below the screen cannot be seen',
      );
      parts.add((element.widget as Text).data ?? '');
    }
    return _squash(parts.join(' '));
  }

  bool canGo(WidgetTester tester, String tooltip) =>
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, _icon(tooltip)))
          .onPressed !=
      null;

  Future<void> press(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  Future<List<String>> forward(WidgetTester tester) async {
    final screens = [shown(tester)];
    while (canGo(tester, 'Next page')) {
      await press(tester, 'Next page');
      screens.add(shown(tester));
      expect(screens.length, lessThan(200));
    }
    return screens;
  }

  testWidgets('paging forward shows every word once, each screen fits', (
    tester,
  ) async {
    await open(tester);
    final screens = await forward(tester);
    expect(screens.length, greaterThan(3));
    expect(screens.join(' '), _squash(_book));
  });

  testWidgets('back returns to each previous screen start', (tester) async {
    await open(tester);
    final screens = await forward(tester);
    for (final screen in screens.reversed.skip(1)) {
      await press(tester, 'Previous page');
      expect(shown(tester), screen);
    }
    expect(canGo(tester, 'Previous page'), isFalse);
  });

  testWidgets('the saved position is the first character shown', (
    tester,
  ) async {
    await open(tester);
    await press(tester, 'Next page');
    await press(tester, 'Next page');
    final first = shown(tester).split(' ').first;
    final saved = await api.readingPosition(ebookIsbn);
    expect(_book.substring(saved!).startsWith(first), isTrue);
  });

  testWidgets('back from a reopened place leaves no gap before it', (
    tester,
  ) async {
    final words = _squash(_book).split(' ');
    final at = _book.indexOf(words[700]);
    await api.savePosition(ebookIsbn, at);
    await open(tester);
    final here = shown(tester).split(' ');
    expect(here.first, words[700]);
    await press(tester, 'Previous page');
    final before = shown(tester).split(' ');
    expect(words.indexOf(before.first), lessThan(700));
    expect(words.indexOf(before.last), greaterThanOrEqualTo(699));
  });

  testWidgets('a taller bar (a running session) re-fits the screen', (
    tester,
  ) async {
    await open(tester);
    await press(tester, 'Next page');
    final first = shown(tester).split(' ').first;
    await tester.tap(find.text('Start reading here'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reading since'), findsOneWidget);
    expect(shown(tester).split(' ').first, first); // and it fits
    final start = await api.readingStart(ebookIsbn);
    expect(_book.substring(start!.offset).startsWith(first), isTrue);
  });

  testWidgets('a font change keeps the first word and repaginates', (
    tester,
  ) async {
    await open(tester);
    await press(tester, 'Next page');
    final before = shown(tester);
    await press(tester, 'Larger text');
    final after = shown(tester);
    expect(after.split(' ').first, before.split(' ').first);
    expect(after.length, lessThan(before.length));
    final rest = await forward(tester);
    expect(
      _squash(_book).endsWith(rest.join(' ')),
      isTrue,
      reason: 'from the anchor on, nothing is skipped',
    );
  });
}

IconData _icon(String tooltip) =>
    tooltip == 'Next page' ? Icons.chevron_right : Icons.chevron_left;
