// The failed strip on the photos screen: one sideways row however many
// failed, a full page of the grid under it, and each photo reachable.

import 'package:book_guard_app/src/screens/failed_photo_card.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/photos_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart' show settle;
import 'support/finders_read.dart';
import 'support/fit_support.dart';

void main() {
  testWidgets('Many failed photos: one sideways strip over a full grid', (
    tester,
  ) async {
    final api = await openHome(tester, 'read', unread: 9);
    await tester.tap(spoken('photos'));
    await settle(tester, 60);
    expectNoVerticalScroll(tester);
    // One row of cards that scrolls sideways, however many failed.
    final cards = find.byType(FailedPhotoCard);
    final stripFinder = find
        .ancestor(of: cards.first, matching: find.byType(Scrollable))
        .first;
    final strip = tester.state<ScrollableState>(stripFinder);
    expect(strip.position.axis, Axis.horizontal);
    expect(strip.position.maxScrollExtent, greaterThan(0));
    final tops = {
      for (final e in cards.evaluate())
        tester.getRect(find.byWidget(e.widget)).top,
    };
    expect(tops, hasLength(1), reason: 'one row');
    // The grid below keeps a full page of 15 tiles, none cut off.
    final view = tester.getRect(find.byType(PhotosScreen));
    const bottom = (2400 - 63) / 2.625;
    var tiles = 0;
    for (var i = 0; i < 40; i++) {
      final tile = find.byKey(ValueKey('photo-p$i.jpg'));
      if (tile.evaluate().isEmpty) continue;
      final r = tester.getRect(tile);
      if (r.left >= view.right || r.right <= view.left) continue;
      tiles++;
      expect(r.bottom, lessThanOrEqualTo(bottom + 0.5), reason: 'p$i cut off');
    }
    expect(tiles, 15);
    expect(find.byKey(const ValueKey('fit-grid-dot-1')), findsOneWidget);
    // A failed photo opens the grid's photo view; send it again from there.
    final thumb = find.byKey(const ValueKey('failed-photo-failed3.jpg'));
    await tester.scrollUntilVisible(thumb, 300, scrollable: stripFinder);
    await settle(tester, 20);
    expectTappable(tester, thumb);
    await tester.tap(thumb);
    await settle(tester, 20);
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(RemoteImage)),
      findsOneWidget,
    );
    final retry = find.descendant(of: dialog, matching: spoken('Send again'));
    expectTappable(tester, retry);
    final before = api.flushes;
    await tester.tap(retry);
    await settle(tester, 20);
    expect(api.flushes, greaterThan(before));
    // Gone: the screen as it was.
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(20, 120));
      await settle(tester, 20);
    }
    expect(find.byType(Dialog), findsNothing);
    expectNoVerticalScroll(tester);
    expect(cards, findsWidgets);
    expectTappable(tester, find.byKey(const ValueKey('photo-p0.jpg')));
  });
}
