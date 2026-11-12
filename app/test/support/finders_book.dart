/// Finders for the text-free book screens: icons by their spoken label,
/// fields by their icon caption, cues by kind or glyph. Nothing here reads
/// a painted word.
library;

import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The [Icon] whose spoken label is [label] (a glyph button's glyph too).
Finder iconLabeled(String label) =>
    find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label);

/// The [IconField] captioned [label] for screen readers.
Finder fieldLabeled(String label) =>
    find.byWidgetPredicate((w) => w is IconField && w.semanticLabel == label);

/// The text box inside [fieldLabeled].
Finder inputLabeled(String label) =>
    find.descendant(of: fieldLabeled(label), matching: find.byType(TextField));

/// Types [text] into the field captioned [label].
Future<void> typeInto(WidgetTester tester, String label, String text) async {
  await tester.enterText(inputLabeled(label), text);
  await tester.pump();
}

/// Whether the field captioned [label] draws its error border.
bool fieldIsRed(WidgetTester tester, String label) =>
    tester.widget<IconField>(fieldLabeled(label)).errorBorder;

/// The button whose glyph has the spoken label [label].
Finder buttonLabeled(String label) => find.ancestor(
  of: iconLabeled(label),
  matching: find.byWidgetPredicate(
    (w) => w is ButtonStyleButton || w is IconButton,
  ),
);

/// Whether the button labelled [label] can be pressed.
bool pressable(WidgetTester tester, String label) {
  final widget = tester.widget(buttonLabeled(label).first);
  return widget is ButtonStyleButton
      ? widget.onPressed != null
      : (widget as IconButton).onPressed != null;
}

/// Taps the button labelled [label], scrolling it into view first.
Future<void> tapLabeled(WidgetTester tester, String label) async {
  await tester.ensureVisible(iconLabeled(label).first);
  await tester.pump();
  await tester.tap(iconLabeled(label).first);
}

/// A status chip of [kind].
Finder cueOf(CueKind kind) =>
    find.byWidgetPredicate((w) => w is StatusCue && w.cue.kind == kind);

/// A status chip drawing [glyph].
Finder cueGlyph(IconData glyph) =>
    find.byWidgetPredicate((w) => w is StatusCue && w.cue.glyph == glyph);

/// A status chip with the spoken label [label].
Finder cueLabeled(String label) => find.byWidgetPredicate(
  (w) => w is StatusCue && w.cue.semanticLabel == label,
);

/// The number [value] painted inside [of].
Finder glyphNumber(Finder of, String value) =>
    find.descendant(of: of, matching: find.text(value));

/// Presses [target] and holds it for [time] (a hold-to-confirm ring).
Future<void> holdFor(
  WidgetTester tester,
  Finder target, [
  Duration time = const Duration(milliseconds: 1000),
]) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  // The ring's ticker starts at the first frame after the press.
  await tester.pump();
  await tester.pump(time);
  await gesture.up();
  await tester.pump();
}
