import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/local_store.dart';

/// Everything bound for the PC -- photos, their sidecar notes, requests,
/// error entries -- is stored on the phone first and sent oldest first.
///
/// So reading never depends on the PC being on: a photo taken while it is
/// off waits here and goes up the next time the share answers. Order is
/// kept (a photo's sidecar before the photo, a stop before its summary),
/// so sending stops at the first failure rather than skipping ahead.
class Outbox {
  /// Creates an outbox over [store], sending through [dav].
  new(this.store, this.dav, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Where waiting items live.
  final LocalStore store;

  /// The share.
  final DavClient dav;

  final DateTime Function() _clock;
  int _seq = 0;
  Future<int>? _flushing;

  /// Why the last send stopped, or null if everything went.
  DavException? lastError;

  static const _dir = 'outbox/';
  static const _pathSuffix = '.path';
  static const _root = 'Reading';

  /// Queues [bytes] for `Reading/[path]`. Call [flush] to send.
  Future<void> put(String path, Uint8List bytes) async {
    final stamp = _clock().microsecondsSinceEpoch.toString().padLeft(20, '0');
    final id = '$_dir$stamp-${(_seq++).toString().padLeft(6, '0')}';
    await store.write('$id.body', bytes);
    // The path goes last: an item only exists once both parts do.
    await store.write('$id$_pathSuffix', Uint8List.fromList(utf8.encode(path)));
  }

  /// How many items are waiting.
  Future<int> pending() async =>
      (await store.list(_dir)).where((n) => n.endsWith(_pathSuffix)).length;

  /// Sends what is waiting, oldest first; returns how many still wait.
  /// Concurrent calls share one run.
  Future<int> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<int> _flush() async {
    final items = [
      for (final n in await store.list(_dir))
        if (n.endsWith(_pathSuffix)) n,
    ];
    for (final (i, name) in items.indexed) {
      final id = name.substring(0, name.length - _pathSuffix.length);
      final path = utf8.decode(await store.read(name) ?? const []);
      final body = await store.read('$id.body');
      if (body != null) {
        try {
          await dav.put('$_root/$path', body);
        } on DavException catch (error) {
          lastError = error;
          return items.length - i;
        }
      }
      await store.delete(name);
      await store.delete('$id.body');
    }
    lastError = null;
    return 0;
  }
}
