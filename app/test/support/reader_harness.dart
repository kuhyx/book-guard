import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:book_guard_app/src/screens/ebook_scroll.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// Opens [EbookReaderScreen] from a button, the way the Read tab pushes it,
/// so popping it can be observed.
class ReaderHarness {
  /// Creates the harness over [api] and [ebook]; [now] is the clock.
  new(this.api, this.ebook, this.now);

  /// The device store.
  final FakeApi api;

  /// The book.
  final Ebook ebook;

  /// Now, as the reader sees it; move it on between taps.
  DateTime now;

  /// What the reader popped with, once it closed.
  AppSession? closedWith;

  /// Whether the reader has closed.
  bool closed = false;

  /// Pushes the reader and lets it load.
  Future<void> open(
    WidgetTester tester, {
    int? latestPage,
    int? paperStart,
  }) async {
    closed = false;
    closedWith = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
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
                  closed = true;
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

  /// The reader's widget type, for finders.
  Type get screenType => EbookReaderScreen;

  /// The scroll view's state: where the reader is, as laid out.
  BookScrollState scroll(WidgetTester tester) =>
      tester.state<BookScrollState>(find.byType(BookScroll));

  /// The first visible character, read from the layout.
  int shown(WidgetTester tester) => scroll(tester).firstVisibleOffset()!;

  /// Taps the right (forward) or left (back) part of the screen.
  Future<void> tapSide(WidgetTester tester, {required bool right}) async {
    final box = tester.getRect(find.byType(EbookReaderScreen));
    await tester.tapAt(
      Offset(box.left + box.width * (right ? 0.9 : 0.1), box.center.dy),
    );
    await tester.pumpAndSettle();
  }

  /// [times] screens forward by tapping the right side.
  Future<void> forward(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tapSide(tester, right: true);
    }
  }

  /// The right-to-left swipe that closes the reader.
  Future<void> swipeOut(WidgetTester tester) async {
    await tester.fling(
      find.byType(EbookReaderScreen),
      const Offset(-300, 0),
      1500,
    );
    await tester.pumpAndSettle();
  }
}
