import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';
import '../support/library_json.dart';

Uint8List _b(String text) => Uint8List.fromList(utf8.encode(text));

/// Lists a note file that is gone by the time it is read.
class _GhostStore extends MemoryStore {
  @override
  Future<List<String>> list(String prefix) async => [
    ...await super.list(prefix),
    if (prefix == 'notes/') 'notes/ghost.json',
  ];
}

Note _note(
  String id, {
  String isbn = '9780735211292',
  String text = 'x',
  int? page,
  DateTime? created,
  DateTime? updated,
}) => Note(
  id: id,
  isbn: isbn,
  text: text,
  page: page,
  createdAt: created ?? DateTime.utc(2026, 10, 3),
  updatedAt: updated ?? created ?? DateTime.utc(2026, 10, 3),
);

void main() {
  late FakeShare share;
  late LocalStore store;
  late GuardApi api;

  GuardApi build(LocalStore s) => GuardApi(
    share.dav(),
    store: s,
    random: Random(1),
    pollEvery: Duration.zero,
    timeout: const Duration(milliseconds: 50),
  );

  setUp(() {
    share = FakeShare();
    store = MemoryStore();
    api = build(store);
  });

  group('library.json', () {
    test('is null before the PC ever wrote one', () async {
      expect(await api.loadLibrary(), isNull);
      expect(await api.cachedLibrary(), isNull);
    });

    test("the PC's copy is kept on the device", () async {
      share.putText('Reading/library.json', jsonEncode(libraryJson()));
      expect((await api.loadLibrary())!.books.length, 3);
      share.down = true;
      expect((await api.loadLibrary())!.books.length, 3, reason: 'offline');
      expect((await api.cachedLibrary())!.books.first.title, 'Atomic Habits');
    });

    test('an unreadable kept copy is null', () async {
      await store.write('library.json', _b('{not json'));
      expect(await api.cachedLibrary(), isNull);
      await store.write('library.json', _b('[1]'));
      expect(await api.cachedLibrary(), isNull);
    });
  });

  group('notesOf', () {
    final book = Library.fromJson(libraryJson()).books.first;

    test("is the PC's notes when the device has none", () async {
      expect((await api.notesOf(book)).map((n) => n.id), ['n1']);
    });

    test('the newer edit of a note wins, either side', () async {
      await store.write(
        'notes/n1.json',
        _b(
          jsonEncode(
            _note(
              'n1',
              text: 'edited here',
              updated: DateTime.utc(2026, 10, 9),
            ).toJson(),
          ),
        ),
      );
      expect((await api.notesOf(book)).single.text, 'edited here');
      await store.write(
        'notes/n1.json',
        _b(
          jsonEncode(
            _note(
              'n1',
              text: 'older',
              updated: DateTime.utc(2026, 10),
            ).toJson(),
          ),
        ),
      );
      expect((await api.notesOf(book)).single.text, 'from the PC');
    });

    test("other books' notes are left out; order is page, then age", () async {
      Future<void> put(Note n) =>
          store.write('notes/${n.id}.json', _b(jsonEncode(n.toJson())));
      await put(_note('late', page: 30));
      await put(_note('unpaged', created: DateTime.utc(2026, 10)));
      await put(_note('elsewhere', isbn: 'other', page: 1));
      await put(_note('twin', page: 12, created: DateTime.utc(2026, 10, 2)));
      final ids = (await api.notesOf(book)).map((n) => n.id);
      expect(ids, ['twin', 'n1', 'late', 'unpaged']);
    });

    test('a listed note that vanished is skipped', () async {
      final ghost = build(_GhostStore());
      expect((await ghost.notesOf(book)).map((n) => n.id), ['n1']);
    });
  });

  test('queuedOnPhone until library.json lists that edit', () {
    final book = Library.fromJson(libraryJson()).books.first;
    final pcTime = DateTime.utc(2026, 10, 3, 10);
    expect(queuedOnPhone(book, _note('n1', updated: pcTime)), isFalse);
    expect(
      queuedOnPhone(book, _note('n1', updated: DateTime.utc(2026, 10))),
      isFalse,
    );
    expect(
      queuedOnPhone(book, _note('n1', updated: DateTime.utc(2026, 10, 9))),
      isTrue,
    );
    expect(queuedOnPhone(book, _note('new')), isTrue);
  });

  test('deviceNotes lists every book; mergeNotes keeps one book', () async {
    final book = Library.fromJson(libraryJson()).books.first;
    await store.write('notes/a.json', _b(jsonEncode(_note('a').toJson())));
    await store.write(
      'notes/b.json',
      _b(jsonEncode(_note('b', isbn: 'other').toJson())),
    );
    final device = await api.deviceNotes();
    expect(device.map((n) => n.id).toSet(), {'a', 'b'});
    expect(mergeNotes(book, device).map((n) => n.id), ['n1', 'a']);
  });

  group('saveNote', () {
    test(
      'keeps the note and queues a note request with a pending marker',
      () async {
        final note = _note('n9', text: 'remember', page: 7);
        await api.saveNote(note);
        expect(
          Note.fromJson(
            jsonDecode(utf8.decode((await store.read('notes/n9.json'))!))
                as Map<String, dynamic>,
          ).text,
          'remember',
        );
        final sent = share.files.entries.singleWhere(
          (e) => e.key.startsWith('Reading/requests/'),
        );
        final request =
            jsonDecode(utf8.decode(sent.value)) as Map<String, dynamic>;
        expect(request['type'], 'note');
        expect(request['note_id'], 'n9');
        expect(request['text'], 'remember');
        expect(request['page'], 7);
        expect(request['isbn'], '9780735211292');
        expect(request.containsKey('id'), isTrue);
        expect(request['id'], isNot('n9'));
        final marker = (await store.list('pending/')).single;
        expect(marker, 'pending/${request['id']}');
        expect(utf8.decode((await store.read(marker))!), 'Note');
      },
    );

    test('offline it waits in the outbox, the note still shows', () async {
      share.down = true;
      await api.saveNote(_note('n9', text: 'later'));
      expect(share.files, isEmpty);
      expect(await api.outbox.pending(), 1);
      final book = Library.fromJson(libraryJson()).books.first;
      expect((await api.notesOf(book)).map((n) => n.text), contains('later'));
    });
  });
}
