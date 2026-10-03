import 'dart:io';
import 'dart:typed_data';

import 'package:book_guard_app/src/local_store.dart' as api;
import 'package:book_guard_app/src/local_store_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('book_guard_store'));
  tearDown(() => root.deleteSync(recursive: true));

  test('files: write, read, list by prefix, delete', () async {
    final store = FileStore(Directory('${root.path}/store'));
    expect(await store.list(''), isEmpty); // no folder yet
    expect(await store.read('a'), isNull);
    await store.write('outbox/1.body', Uint8List.fromList([1]));
    await store.write('outbox/1.path', Uint8List.fromList([2]));
    await store.write('journal.json', Uint8List.fromList([3]));
    File('${root.path}/store/outbox/2.body.part').writeAsBytesSync([9]);
    expect(await store.list('outbox/'), ['outbox/1.body', 'outbox/1.path']);
    expect(await store.read('journal.json'), [3]);
    await store.delete('journal.json');
    await store.delete('journal.json'); // already gone: fine
    expect(await store.read('journal.json'), isNull);
  });

  test('memory store behaves the same', () async {
    final store = api.MemoryStore();
    await store.write('b', Uint8List.fromList([1]));
    await store.write('a', Uint8List.fromList([2]));
    expect(await store.list(''), ['a', 'b']);
    await store.delete('a');
    expect(await store.read('a'), isNull);
  });

  test('without a platform folder the store is kept in memory', () async {
    expect(await api.createLocalStore(), isA<api.MemoryStore>());
  });
}
