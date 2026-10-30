import 'package:book_guard_app/src/ebook_paragraphs.dart';
import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/reader_harness.dart';

/// Words of uneven length, so lines wrap at different places.
String _words(int n, int seed) =>
    [for (var i = 0; i < n; i++) 'w${seed}_$i${'x' * ((i * 7 + seed) % 9)}']
        .join(' ');

/// Headings, breaks and paragraphs far longer than a screen.
final String _book = [
  'ROZDZIAŁ I',
  _words(40, 1),
  _words(30, 2),
  '* * *',
  _words(900, 3),
  _words(25, 4),
  'ROZDZIAŁ II',
  _words(20, 7),
  _words(300, 5),
  _words(12, 6),
].join('\n\n');

void main() {
  late FakeApi api;
  late ReaderHarness reader;

  setUp(() {
    api = FakeApi();
    final ebook = Ebook(EbookMap.fromJson(ebookMapJson(text: _book))!, _book);
    reader = ReaderHarness(api, ebook, DateTime.utc(2026, 10, 23, 18));
  });

  /// The start of word [n] of paragraph [para] (0-based, in the text).
  int wordAt(int para, int n) {
    final start = BookParagraphs.split(_book).all[para].start;
    var at = start;
    for (var i = 0; i < n; i++) {
      at = _book.indexOf(' ', at) + 1;
    }
    return at;
  }

  testWidgets('reopens on the line holding the saved character', (
    tester,
  ) async {
    final saved = wordAt(8, 200); // deep inside an indented paragraph
    await api.savePosition(ebookIsbn, saved);
    await reader.open(tester);
    final shown = reader.shown(tester);
    expect(shown, lessThanOrEqualTo(saved));
    expect(saved - shown, lessThan(40), reason: 'the same line');
    expect(
      _book[shown - 1],
      ' ',
      reason:
          'a line starts on a word: the indent placeholder is not a '
          'character of the book',
    );
  });

  testWidgets('an indented paragraph start maps to itself exactly', (
    tester,
  ) async {
    final start = BookParagraphs.split(_book).all[5].start;
    await api.savePosition(ebookIsbn, start);
    await reader.open(tester);
    expect(reader.shown(tester), start);
  });

  testWidgets('paging on reaches the end and stays there', (tester) async {
    await reader.open(tester);
    var last = -1;
    for (var i = 0; i < 80 && reader.shown(tester) != last; i++) {
      last = reader.shown(tester);
      await reader.forward(tester);
    }
    expect(reader.shown(tester), last, reason: 'the end does not move');
    expect(last, greaterThan(_book.indexOf('w5_')));
  });

  testWidgets('paging back from a reopened place goes before it', (
    tester,
  ) async {
    final saved = wordAt(4, 700);
    await api.savePosition(ebookIsbn, saved);
    await reader.open(tester);
    final here = reader.shown(tester);
    await reader.tapSide(tester, right: false);
    final before = reader.shown(tester);
    expect(before, lessThan(here));
    expect(here - before, greaterThan(200));
  });

  testWidgets('a wide window sets 20 px in a centred column', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await reader.open(tester);
    expect(reader.scroll(tester).widget.fontSize, 20);
    final text = tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    );
    final box = text.first;
    final left = box.localToGlobal(Offset.zero).dx;
    expect(box.size.width, ReadingStyle.measure(20));
    expect(left, closeTo((1600 - ReadingStyle.measure(20)) / 2, 1));
  });

  testWidgets('the text is black on white, unscaled by the system', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await reader.open(tester);
    final rich = tester.widgetList<RichText>(find.byType(RichText)).first;
    expect(rich.text.style?.color, ReadingStyle.ink);
    expect(rich.textScaler, TextScaler.noScaling);
    expect(rich.text.style?.fontFamily, ReadingStyle.fontFamily);
  });
}
