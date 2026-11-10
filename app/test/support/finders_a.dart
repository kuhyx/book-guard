/// Finders for the text-free status / home / pace screens: icons, spoken
/// labels and cue kinds instead of strings.
library;

import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [Icon] whose spoken label is [label].
Finder iconLabeled(String label) => find.byWidgetPredicate(
  (w) => w is Icon && w.semanticLabel == label,
  description: 'icon spoken "$label"',
);

/// [icon] inside the bottom navigation bar (the content shares glyphs).
Finder navTab(IconData icon) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.byIcon(icon),
);

/// The cue chip in the snackbar on screen.
Finder get shownCue => find.descendant(
  of: find.byType(SnackBar),
  matching: find.byType(StatusCue),
);

/// The kind of the single cue on screen; fails when there is not one.
CueKind shownCueKind(WidgetTester tester) =>
    tester.widget<StatusCue>(shownCue).cue.kind;

/// [icon] inside the cue on screen.
Finder inShownCue(IconData icon) =>
    find.descendant(of: shownCue, matching: find.byIcon(icon));

/// The [n]th text field of a page (settings: url, user, password).
Finder fieldAt(int n) => find.byType(TextField).at(n);

/// The filled (main action) button of a page.
Finder get mainButton => find.byType(FilledButton).first;
