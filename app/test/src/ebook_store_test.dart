import 'dart:convert';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ebook_fixture.dart';
import '../support/fake_api.dart';
import '../support/fake_share.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi()..files.addAll(ebookFiles());
  });

  EbookRef ref() => ebookState().book!.ebook!;

  group('download', () {
    test('the text and its map are kept on the device', () async {
      final book = await api.syncEbook(ebookIsbn, ref());
      expect(book!.text, ebookText);
      expect(book.map.textSha, shaOf(ebookText));
      api.files.clear(); // the PC is gone
      final kept = await api.cachedEbook(ebookIsbn);
      expect(kept!.text, ebookText);
      expect(kept.map.pageAt(0), 10);
    });

    test('an unchanged text is not downloaded again', () async {
      await api.syncEbook(ebookIsbn, ref());
      api.fetched.clear();
      await api.syncEbook(ebookIsbn, ref());
      expect(api.fetched, ['ebooks/$ebookIsbn.map.json']);
    });

    test('a text that does not match its sha256 is refused', () async {
      api.files['ebooks/$ebookIsbn.txt'] = utf8.encode('tampered');
      expect(await api.syncEbook(ebookIsbn, ref()), isNull);
      expect(await api.cachedEbook(ebookIsbn), isNull);
    });

    test('offline it keeps what it has', () async {
      await api.syncEbook(ebookIsbn, ref());
      final share = FakeShare()..down = true;
      final offline = GuardApi(share.dav(), store: api.store);
      final kept = await offline.syncEbook(ebookIsbn, ref());
      expect(kept!.text, ebookText);
    });

    test('a missing or broken map leaves nothing to read', () async {
      api.files.remove('ebooks/$ebookIsbn.map.json');
      expect(await api.syncEbook(ebookIsbn, ref()), isNull);
      api.files['ebooks/$ebookIsbn.map.json'] = utf8.encode('[1]');
      expect(await api.syncEbook(ebookIsbn, ref()), isNull);
      api.files['ebooks/$ebookIsbn.map.json'] = utf8.encode('{nope');
      expect(await api.syncEbook(ebookIsbn, ref()), isNull);
      api.files.remove('ebooks/$ebookIsbn.txt');
      api.files['ebooks/$ebookIsbn.map.json'] =
          ebookFiles()['ebooks/$ebookIsbn.map.json']!;
      expect(await api.syncEbook(ebookIsbn, ref()), isNull);
    });
  });

  group('reading', () {
    test('the position and the font size are remembered', () async {
      expect(await api.readingPosition(ebookIsbn), isNull);
      await api.savePosition(ebookIsbn, 1234);
      expect(await api.readingPosition(ebookIsbn), 1234);
      expect(await api.fontSize(), 18);
      await api.saveFontSize(22);
      expect(await api.fontSize(), 22);
    });

    test('a start is kept at the tap and survives a restart', () async {
      final start = ReadingStart(
        id: 'abcdef0123456789',
        isbn: ebookIsbn,
        offset: 400,
        startedAt: DateTime.utc(2026, 10, 23, 18),
        textSha: shaOf(ebookText),
      );
      await api.startReading(start);
      final restarted = GuardApi(FakeShare().dav(), store: api.store);
      final kept = await restarted.readingStart(ebookIsbn);
      expect(kept!.offset, 400);
      expect(kept.startedAt, DateTime.utc(2026, 10, 23, 18));
      await restarted.cancelReading(ebookIsbn);
      expect(await restarted.readingStart(ebookIsbn), isNull);
    });

    test('stopping queues the session and keeps it for its summary', () async {
      final book = await api.syncEbook(ebookIsbn, ref());
      final start = ReadingStart(
        id: 'abcdef0123456789',
        isbn: ebookIsbn,
        offset: 0,
        startedAt: DateTime.utc(2026, 10, 23, 18),
        textSha: book!.map.textSha,
      );
      await api.startReading(start);
      final end = book.map.offsetAt(20);
      final done = await api.stopReading(
        start,
        end,
        book.map,
        DateTime.utc(2026, 10, 23, 19),
      );
      expect(done.sessionId, 'session:ebook-abcdef0123456789');
      expect((done.startPage, done.endPage), (10, 20));
      expect(await api.readingStart(ebookIsbn), isNull);
      final info = (await api.appSessions()).single.info;
      expect(info.id, 'session:ebook-abcdef0123456789');
      expect(info.pages, 10);
      expect(info.minutes, 60);
      expect(info.status, 'needs-quiz');
      expect(info.estimated, isTrue);
      expect(info.span, '≈ p. 10-20');
      final queued = await api.store.list('outbox/');
      final path = queued.firstWhere((n) => n.endsWith('.path'));
      final body = queued.firstWhere(
        (n) => n == '${path.substring(0, path.length - 5)}.body',
      );
      final request = jsonDecode(
        utf8.decode((await api.store.read(body))!),
      ) as Map<String, dynamic>;
      expect(request['type'], 'ebook_session');
      expect(request['session'], 'abcdef0123456789');
      expect(request['start_offset'], 0);
      expect(request['end_offset'], end);
      expect(request['text_sha'], shaOf(ebookText));
      expect(request['started_at'], '2026-10-23T18:00:00.000Z');
      await api.forgetAppSession(done.key);
      expect(await api.appSessions(), isEmpty);
    });

    test('a session the PC refused is known as refused', () async {
      final share = FakeShare()
        ..answer = (r) => {'id': r['id'], 'ok': false, 'message': 'no'};
      final real = GuardApi(share.dav(), store: api.store);
      share.files['Reading/ebooks/$ebookIsbn.map.json'] =
          ebookFiles()['ebooks/$ebookIsbn.map.json']!;
      share.files['Reading/ebooks/$ebookIsbn.txt'] =
          ebookFiles()['ebooks/$ebookIsbn.txt']!;
      final book = await real.syncEbook(ebookIsbn, ref());
      final start = ReadingStart(
        id: 'abcdef0123456789',
        isbn: ebookIsbn,
        offset: 0,
        startedAt: DateTime.utc(2026, 10, 23, 18),
        textSha: book!.map.textSha,
      );
      final done = await real.stopReading(
        start,
        book.map.offsetAt(20),
        book.map,
        DateTime.utc(2026, 10, 23, 19),
      );
      expect(await real.refused(done), isFalse);
      final answers = await real.collectAnswers();
      expect(answers.single.response.ok, isFalse);
      expect(await real.refused(done), isTrue);
    });
  });
}
