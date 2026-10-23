import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/journal_fixtures.dart';

void main() {
  late MemoryStore store;
  const e = journalEntry;
  final t0 = journalStart;

  setUp(() => store = MemoryStore());

  test('once listed, a photo stays known after it leaves the window', () async {
    final journal = Journal(store);
    await journal.add(e('a', 'start', 104, 0));
    await journal.add(e('b', 'stop', 151, 50));
    await journal.markSeen(windowState(photos: ['a', 'b']));
    final all = await journal.load();
    expect(all.map((x) => x.seen), [true, true]);
    // Later the window moved on and lists neither (its one photo is
    // older, so time decides nothing): the marks alone keep them known.
    expect(localView(windowState(photos: ['zzz']), all), isNull);
    // An entry stored before seen marks existed reads as unseen.
    expect(
      JournalEntry.fromJson(all.first.toJson()..remove('seen')).seen,
      isFalse,
    );
  });

  test('entries added at once are all kept', () async {
    final journal = Journal(store);
    await Future.wait([
      for (var i = 0; i < 20; i++) journal.add(e('n$i', 'start', i, i)),
      journal.markSeen(windowState(photos: ['n0'])),
    ]);
    final all = await journal.load();
    expect(all, hasLength(20));
    expect(all.first.seen, isTrue);
  });

  test('journal entries round-trip and the journal is capped', () async {
    final journal = Journal(store);
    for (var i = 0; i < Journal.keep + 1; i++) {
      await journal.add(e('n$i', 'start', i, i));
    }
    final all = await journal.load();
    expect(all, hasLength(Journal.keep));
    expect(all.first.name, 'n1');
    expect(all.last.takenAt, t0.add(const Duration(minutes: Journal.keep)));
  });
}
