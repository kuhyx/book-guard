import 'dart:typed_data';

import 'package:book_guard_app/src/local_store_none.dart'
    if (dart.library.io) 'package:book_guard_app/src/local_store_io.dart'
    as platform;

/// The app's own small key -> bytes storage: the outbox, the photo journal,
/// the last snapshot and the error log. Names may contain `/`.
abstract interface class LocalStore {
  /// The bytes stored under [name], or null.
  Future<Uint8List?> read(String name);

  /// Stores [bytes] under [name], replacing what was there.
  Future<void> write(String name, Uint8List bytes);

  /// Forgets [name]; missing is fine.
  Future<void> delete(String name);

  /// Every stored name starting with [prefix], sorted.
  Future<List<String>> list(String prefix);
}

/// A [LocalStore] in memory: the web build (served by the PC itself, so
/// nothing needs to survive) and tests.
class MemoryStore implements LocalStore {
  final _items = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String name) async => _items[name];

  @override
  Future<void> write(String name, Uint8List bytes) async =>
      _items[name] = Uint8List.fromList(bytes);

  @override
  Future<void> delete(String name) async => _items.remove(name);

  @override
  Future<List<String>> list(String prefix) async =>
      [..._items.keys.where((k) => k.startsWith(prefix))]..sort();
}

/// Runs actions one at a time, in call order, so one read-modify-write of
/// a stored file never interleaves with another (two at once used to drop
/// the first one's change).
class Serial {
  // Null until the first action: a ready future made up front belongs to
  // the zone that built this, and a test's fake clock would never run it.
  Future<void>? _last;

  /// Runs [action] after every action queued before it.
  Future<T> run<T>(Future<T> Function() action) {
    final last = _last;
    final result = last == null
        ? Future.sync(action)
        : last.then((_) => action());
    _last = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// Files on the phone, memory on the web.
Future<LocalStore> createLocalStore() => platform.createLocalStore();
