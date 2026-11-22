import 'package:book_guard_app/src/screens/stale_captures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fake_reader.dart';
import '../../support/finders_read.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);
final _now = DateTime(2026, 11, 22, 11, 31);

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester) async {
    await api.captures.keep(
      'old',
      'start',
      'IMG.jpg',
      _bytes,
      at: DateTime(2026, 10, 27, 20, 15),
    );
    await api.captures.keep('new', 'stop', 'NEW.jpg', _bytes, at: _now);
    await pumpTab(
      tester,
      StaleCaptures(
        api: api,
        reader: FakeReader(
          fakeScan([(473, (left: 17, top: 54, right: 23, bottom: 58))]),
        ),
        clock: () => _now,
        onChanged: () async {},
      ),
    );
    await settle(tester, 10);
  }

  testWidgets('a 26-day-old start photo shows with its page read', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('473'), findsOneWidget); // the fresh one is not listed
    expect(spoken('Start reading'), findsNothing);
    await tester.tap(spoken('Keep as a page photo'));
    await settle(tester, 10);
    // The keypad comes up holding 473: one tap sends it.
    await tester.tap(spoken('Send the typed page number'));
    await settle(tester, 10);
    expect(api.photos.keys, ['kept_IMG.jpg']);
    expect(api.notes['kept_IMG.jpg']?.page, 473);
    final left = await api.captures.pending();
    expect(left.map((c) => c.id), ['new']);
  });

  testWidgets('delete drops it, nothing is sent', (tester) async {
    await pump(tester);
    await tester.tap(spoken('Delete the stored photo'));
    await settle(tester, 10);
    expect(api.photos, isEmpty);
    expect((await api.captures.pending()).map((c) => c.id), ['new']);
    expect(find.text('473'), findsNothing);
  });
}
