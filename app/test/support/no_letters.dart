import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Any letter in any script. Icons paint a private-use codepoint (category
/// Co), digits are Nd and `·`, `+`, `:` are punctuation, so all of those pass.
final _letter = RegExp(r'\p{L}', unicode: true);

/// The painted strings under [scope]: every `Text`, `RichText` and
/// `EditableText`.
List<String> paintedStrings(Finder scope) {
  final out = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byWidgetPredicate((_) => true))
          .evaluate()) {
    final widget = element.widget;
    if (widget is Text) {
      out.add(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    } else if (widget is RichText) {
      out.add(widget.text.toPlainText());
    } else if (widget is EditableText) {
      out.add(widget.controller.text);
    }
  }
  return out;
}

/// Asserts [scope] paints no word and no tooltip (long-press paints it),
/// and that each icon in [spoken] sits in a control with a spoken label.
///
/// Fails closed: a scope that matches nothing is an error, not a pass.
void expectNoLetters(
  WidgetTester tester,
  Finder scope, {
  List<IconData> spoken = const [],
}) {
  expect(scope, findsOneWidget, reason: 'the scope must be on screen');
  final strings = paintedStrings(scope);
  expect(strings, isNotEmpty, reason: 'nothing painted: wrong scope?');
  final words = strings.where(_letter.hasMatch).toList();
  expect(words, isEmpty, reason: 'painted words: $words');
  expect(
    find.descendant(of: scope, matching: find.byType(Tooltip)),
    findsNothing,
    reason: 'a tooltip paints its message on long-press',
  );
  final handle = tester.ensureSemantics();
  for (final icon in spoken) {
    final control = find.descendant(of: scope, matching: find.byIcon(icon));
    expect(control, findsOneWidget, reason: 'no $icon control');
    final label = tester.getSemantics(control).getSemanticsData().label;
    expect(label.trim(), isNotEmpty, reason: '$icon has no spoken label');
  }
  handle.dispose();
}
