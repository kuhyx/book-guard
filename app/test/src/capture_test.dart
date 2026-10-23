import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

/// The lifecycle events [api] has queued for the PC, oldest first.
Future<List<Map<String, dynamic>>> events(GuardApi api) async => [
  for (final name in await api.store.list('eventbox/'))
    if (name.endsWith('.body'))
      jsonDecode(utf8.decode((await api.store.read(name))!))
          as Map<String, dynamic>,
];

void main() {
  late MemoryStore store;
  late GuardApi api;

  setUp(() {
    store = MemoryStore();
    api = GuardApi(FakeShare().dav(), store: store);
  });

  test('a capture is kept until it is queued or discarded', () async {
    final captures = Captures(store);
    await captures.launching('a1', 'start');
    expect(await captures.launched(), (id: 'a1', label: 'start'));
    final kept = await captures.keep(
      'a1',
      'start',
      'IMG.jpg',
      _b('jpeg'),
      at: DateTime.utc(2026, 10, 23, 8, 6),
    );
    // Back from the camera: the launch is answered.
    expect(await captures.launched(), isNull);
    final [pending] = await captures.pending();
    expect(
      (pending.id, pending.label, pending.fileName, pending.takenAt),
      ('a1', 'start', 'IMG.jpg', DateTime.utc(2026, 10, 23, 8, 6)),
    );
    expect(await captures.bytes(kept), _b('jpeg'));
    await captures.drop(kept);
    expect(await captures.pending(), isEmpty);
    expect(await captures.bytes(kept), isNull);
    await captures.launching('a2', 'stop');
    await captures.landed();
    expect(await captures.launched(), isNull);
  });

  group('after a restart', () {
    test('no camera was open: nothing to do', () async {
      var asked = false;
      await api.recoverCamera(() async {
        asked = true;
        return null;
      });
      expect(asked, isFalse);
      expect(await events(api), isEmpty);
    });

    test(
      "the camera's photo Android kept is stashed under its label",
      () async {
        await api.captures.launching('a1', 'stop');
        await api.recoverCamera(() async => ('IMG_9.jpg', _b('lost')));
        final [capture] = await api.captures.pending();
        expect(
          (capture.id, capture.label, capture.fileName),
          ('a1', 'stop', 'IMG_9.jpg'),
        );
        expect(await api.captures.bytes(capture), _b('lost'));
        expect((await events(api)).single, containsPair('event', 'recovered'));
      },
    );

    test('a camera that never answered is logged as lost', () async {
      await api.captures.launching('a1', 'start');
      await api.recoverCamera(null); // the desktop: nothing to ask
      expect(await api.captures.launched(), isNull);
      expect(await api.captures.pending(), isEmpty);
      final [lost] = await events(api);
      expect(lost, containsPair('event', 'camera-lost'));
      expect(lost, containsPair('attempt', 'a1'));
      expect(lost, containsPair('level', 'event'));
    });
  });
}
