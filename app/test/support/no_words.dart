/// The zero-text guard: nothing painted on screen holds a word, except the
/// content nodes a test names (book titles, authors, grader topics, typed
/// text). Numbers, dates and symbols are fine; tooltips count as painted
/// (a long-press shows them).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _word = RegExp('[A-Za-z]{2,}');

/// Every painted string on screen that still holds a word once each of
/// [content] is cut out of it. Typed field values ([EditableText]) are the
/// user's own and never counted.
List<String> paintedWords(
  WidgetTester tester, {
  Iterable<String> content = const [],
}) {
  final cuts = content.where((c) => c.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final typed = find.byType(EditableText);
  final painted = [
    for (final element in find.byType(RichText).evaluate())
      if (find
          .descendant(of: typed, matching: find.byWidget(element.widget))
          .evaluate()
          .isEmpty)
        (element.widget as RichText).text.toPlainText(),
    for (final tip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      tip.message ?? '',
  ];
  return [
    for (final text in painted)
      if (_word.hasMatch(cuts.fold(text, (left, c) => left.replaceAll(c, ''))))
        text,
  ];
}

/// Fails with the offending strings when anything on screen holds a word.
void expectNoWords(WidgetTester tester, {Iterable<String> content = const []}) {
  final words = paintedWords(tester, content: content);
  // An empty screen proves nothing: the guard needs something painted.
  expect(find.byType(RichText), findsWidgets);
  expect(words, isEmpty, reason: 'painted words: $words');
}
