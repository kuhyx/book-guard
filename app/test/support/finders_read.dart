/// Finders for the Read tab's wordless UI: they match icons, spoken labels
/// and cue kinds, never painted sentences.
library;

import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/pulse_glyph.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [Icon] whose spoken label is [label] (the old wording, never painted).
Finder spoken(String label) => find.byWidgetPredicate(
  (w) => w is Icon && w.semanticLabel == label,
  description: 'icon spoken "$label"',
);

/// A [StatusCue] of [kind].
Finder cueOf(CueKind kind) => find.byWidgetPredicate(
  (w) => w is StatusCue && w.cue.kind == kind,
  description: 'StatusCue $kind',
);

/// A [StatusCue] drawing [icon].
Finder cueWith(IconData icon) => find.byWidgetPredicate(
  (w) => w is StatusCue && w.cue.glyph == icon,
  description: 'StatusCue with $icon',
);

/// The reject badge wearing [glyph].
Finder rejected(RejectGlyph glyph) => find.byIcon(glyph.icon);

/// Any [RejectBadge].
Finder anyRejection() => find.byType(RejectBadge);

/// The [PhotoStatusChip] on screen.
Finder photoChip() => find.byType(PhotoStatusChip);

/// A button (any kind) that holds a [spoken] icon.
Finder buttonSpoken(String label) => find.ancestor(
  of: spoken(label),
  matching: find.byWidgetPredicate(
    (w) => w is FilledButton || w is OutlinedButton || w is IconButton,
  ),
);

/// The platform asks for no animation (a pulse stands still, so the
/// frames can settle).
void noAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The review screen shows the tick and page [page] on the photo.
Finder chosenPage(int page) => find.descendant(
  of: find.byType(PhotoReview),
  matching: find.descendant(
    of: cueOf(CueKind.ok),
    matching: find.text('$page'),
  ),
);

/// The pulsing viewfinder that asks for a box.
Finder pulse() => find.byType(PulseGlyph);

/// The indeterminate bar of a summary with the grader (the length bar has
/// a value; this one has none).
Finder busyBar() => find.byWidgetPredicate(
  (w) => w is LinearProgressIndicator && w.value == null,
  description: 'busy bar',
);

/// Holds [finder] down long enough for a `HoldButton` ring to confirm.
Future<void> hold(WidgetTester tester, Finder finder) async {
  final press = await tester.startGesture(tester.getCenter(finder));
  // Past the press timeout (a scroll view may hold the tap back) ...
  await tester.pump(const Duration(milliseconds: 150));
  // ... then the ring fills.
  await tester.pump(const Duration(milliseconds: 1000));
  await press.up();
  await tester.pump();
}

/// [finder] inside the snackbar on screen.
Finder inSnack(Finder finder) =>
    find.descendant(of: find.byType(SnackBar), matching: finder);
