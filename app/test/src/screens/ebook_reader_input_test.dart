import 'package:book_guard_app/src/ebook_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ebook_fixture.dart';
import '../../support/fake_api.dart';
import '../../support/reader_harness.dart';

void main() {
  late FakeApi api;
  late ReaderHarness reader;

  setUp(() async {
    api = FakeApi()..files.addAll(ebookFiles());
    final ebook = (await api.syncEbook(ebookIsbn, ebookState().book!.ebook!))!;
    reader = ReaderHarness(api, ebook, DateTime.utc(2026, 10, 23, 18));
  });

  testWidgets('a tap on the right moves on a screen and saves it', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    final first = reader.shown(tester);
    await reader.tapSide(tester, right: true);
    final second = reader.shown(tester);
    expect(second, greaterThan(first));
    expect(await api.readingPosition(ebookIsbn), second);
    await reader.tapSide(tester, right: false);
    expect(reader.shown(tester), lessThan(second));
    expect(await api.readingPosition(ebookIsbn), reader.shown(tester));
  });

  testWidgets('a tap in the middle does nothing', (tester) async {
    await reader.open(tester, latestPage: 20);
    final first = reader.shown(tester);
    await tester.tapAt(tester.getCenter(find.byType(reader.screenType)));
    await tester.pumpAndSettle();
    expect(reader.shown(tester), first);
  });

  testWidgets('a screen forward skips nothing: the cut line comes first', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    for (var i = 0; i < 6; i++) {
      final scroll = reader.scroll(tester);
      final top = scroll.firstVisibleOffset()!;
      final bottom = scroll.offsetAt(scroll.viewportHeight - 1)!;
      await reader.tapSide(tester, right: true);
      final next = reader.shown(tester);
      expect(next, greaterThan(top));
      expect(next, lessThanOrEqualTo(bottom), reason: 'screen $i skipped');
    }
  });

  testWidgets('volume down is the next screen, volume up the previous', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    final first = reader.shown(tester);
    final down = await simulateKeyDownEvent(
      LogicalKeyboardKey.audioVolumeDown,
      platform: 'android',
    );
    final up = await simulateKeyUpEvent(
      LogicalKeyboardKey.audioVolumeDown,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(down, isTrue, reason: 'handled: the system volume stays');
    expect(up, isTrue);
    final second = reader.shown(tester);
    expect(second, greaterThan(first));
    expect(await api.readingPosition(ebookIsbn), second);
    expect(
      await simulateKeyDownEvent(
        LogicalKeyboardKey.audioVolumeUp,
        platform: 'android',
      ),
      isTrue,
    );
    await simulateKeyUpEvent(
      LogicalKeyboardKey.audioVolumeUp,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(reader.shown(tester), lessThan(second));
  });

  testWidgets('the desktop keys page too', (tester) async {
    await reader.open(tester, latestPage: 20);
    var at = reader.shown(tester);
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(reader.shown(tester), greaterThan(at), reason: '$key');
      at = reader.shown(tester);
    }
    for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.pageUp]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(reader.shown(tester), lessThan(at), reason: '$key');
      at = reader.shown(tester);
    }
  });

  testWidgets('a finger scroll reads on and is saved', (tester) async {
    await reader.open(tester, latestPage: 20);
    final first = reader.shown(tester);
    await tester.drag(find.byType(reader.screenType), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(reader.closed, isFalse);
    expect(reader.shown(tester), greaterThan(first));
    expect(await api.readingPosition(ebookIsbn), reader.shown(tester));
  });

  testWidgets('a left-to-right swipe does not close it', (tester) async {
    await reader.open(tester, latestPage: 20);
    await tester.fling(
      find.byType(reader.screenType),
      const Offset(300, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(reader.closed, isFalse);
  });

  testWidgets('a slow short right-to-left drag does not close it', (
    tester,
  ) async {
    await reader.open(tester, latestPage: 20);
    await tester.timedDrag(
      find.byType(reader.screenType),
      const Offset(-30, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(reader.closed, isFalse);
  });
}
