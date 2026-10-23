import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/error_log.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late FakeShare share;
  late MemoryStore store;

  setUp(() {
    share = FakeShare();
    store = MemoryStore();
  });

  group('outbox', () {
    test('keeps order, stops at the first failure, resumes later', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('inbox/a.jpg.json', _b('{}'));
      await outbox.put('inbox/a.jpg', _b('jpeg'));
      share.down = true;
      expect(await outbox.flush(), 2);
      expect(outbox.lastError?.status, 0);
      expect(await outbox.pending(), 2);
      share.down = false;
      expect(await outbox.flush(), 0);
      expect(outbox.lastError, isNull);
      expect(share.files.keys, [
        'Reading/inbox/a.jpg.json',
        'Reading/inbox/a.jpg',
      ]);
      expect(await store.list('outbox/'), isEmpty);
    });

    test('an item whose body is gone is dropped', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('x', _b('1'));
      final body = (await store.list('outbox/'))
          .firstWhere((n) => n.endsWith('.body'));
      await store.delete(body);
      expect(await outbox.flush(), 0);
      expect(share.files, isEmpty);
    });

    test('concurrent flushes share one run', () async {
      final outbox = Outbox(store, share.dav());
      await outbox.put('x', _b('1'));
      final both = await Future.wait([outbox.flush(), outbox.flush()]);
      expect(both, [0, 0]);
      expect(share.requests, hasLength(1));
    });
  });

  group('outbox while a send is running', () {
    test('an item queued mid-run is sent by a follow-up run', () async {
      // The camera's photo was queued while the 10 s refresh was sending:
      // its flush() joined that run, which had listed the outbox before the
      // photo -- "Uploaded" was shown for a photo still on the phone.
      final outbox = Outbox(store, share.dav());
      await outbox.put('first', _b('1'));
      final running = outbox.flush();
      await outbox.put('inbox/photo.jpg', _b('2'));
      expect(await outbox.flush(), 0);
      expect(await running, 0);
      expect(share.files.keys, ['Reading/first', 'Reading/inbox/photo.jpg']);
    });
  });

  group('error log', () {
    test('entries logged at once are all kept and all sent', () async {
      final outbox = Outbox(store, share.dav());
      final log = ErrorLog(store, outbox, host: 'phone', random: Random(3));
      await Future.wait([for (var i = 0; i < 20; i++) log.log('x', 'e$i')]);
      final kept = utf8.decode((await store.read('errors.jsonl'))!);
      expect(const LineSplitter().convert(kept), hasLength(20));
      expect(await outbox.pending(), 20);
    });

    test('keeps the newest entries and queues each for the PC', () async {
      final outbox = Outbox(store, share.dav());
      final log = ErrorLog(
        store,
        outbox,
        host: 'phone',
        clock: () => DateTime.utc(2026, 10, 3, 12, 27),
        random: Random(2),
      );
      for (var i = 0; i < ErrorLog.keep + 3; i++) {
        await log.log('upload', 'failed $i', {'n': i});
      }
      final kept = utf8.decode((await store.read('errors.jsonl'))!);
      expect(const LineSplitter().convert(kept), hasLength(ErrorLog.keep));
      expect(kept, isNot(contains('"failed 2"')));
      share.down = true;
      await outbox.flush();
      final report = await log.diagnostics(last: 2);
      expect(report, contains('waiting to send: ${ErrorLog.keep + 3}'));
      expect(report, contains('last send failed'));
      expect(report, contains('"failed ${ErrorLog.keep + 2}"'));
      expect(report, isNot(contains('"failed 0"')));
      share.down = false;
      await outbox.flush();
      final sent = share.files.keys.where(
        (k) => k.startsWith('Reading/logs/phone/'),
      );
      expect(sent, hasLength(ErrorLog.keep + 3));
      final entry = jsonDecode(share.text(sent.first)!) as Map<String, dynamic>;
      expect(entry, containsPair('host', 'phone'));
      expect(entry, containsPair('stage', 'upload'));
    });

    test('an empty log still reports its queue', () async {
      final log = ErrorLog(store, Outbox(store, share.dav()), host: 'desktop');
      expect(await log.diagnostics(), contains('waiting to send: 0'));
    });
  });
}
