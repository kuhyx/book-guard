import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/capture_stage.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';

/// A stored photo of any age can be put on a test install over adb, so a
/// live check can stage the 26-day-old start photo of 2026-10-27.
void main() {
  test('a staged photo becomes a stored capture with its own time', () async {
    final store = MemoryStore();
    final api = GuardApi(FakeShare().dav(), store: store);
    final at = DateTime.parse('2026-10-27T20:15:00+01:00');
    await api.stageCaptures(
      () async => [
        (
          label: 'start',
          at: at,
          name: 'p473.jpg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ],
    );
    final [capture] = await api.captures.pending();
    expect(
      (capture.label, capture.fileName, capture.takenAt),
      ('start', 'p473.jpg', at),
    );
    expect(await api.captures.bytes(capture), [1, 2, 3]);
    // The desktop build has nothing to stage.
    await api.stageCaptures(null);
    expect(await api.captures.pending(), hasLength(1));
  });

  test('the adb manifest names each photo, its label and time', () {
    final rows = parseStageManifest(
      jsonEncode([
        {
          'file': 'p473.jpg',
          'label': 'start',
          'taken_at': '2026-10-27T20:15:00+01:00',
        },
      ]),
    );
    expect(rows, [
      (
        file: 'p473.jpg',
        label: 'start',
        at: DateTime.parse('2026-10-27T20:15:00+01:00'),
      ),
    ]);
  });
}
