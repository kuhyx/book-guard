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
  /// Creates an outbox over [store] (in its folder [dir]), sending through
  /// [dav].
  new(this.store, this.dav, {DateTime Function()? clock, this.dir = 'outbox/'})
    : _clock = clock ?? DateTime.now;

  /// Where waiting items live.
  final LocalStore store;

  /// The share.
  final DavClient dav;

  final DateTime Function() _clock;

  /// The store folder its items live in.
  final String dir;
  int _seq = 0;
  Future<int>? _flushing;
  Future<int>? _followUp;

  /// Why the last send stopped, or null if everything went.
  DavException? lastError;

  /// Told about every send: its `Reading/`-relative path and the error, or
  /// null when it went.
  void Function(String path, DavException? error)? onSent;

  static const _pathSuffix = '.path';
  static const _root = 'Reading';

  /// Queues [bytes] for `Reading/[path]`. Call [flush] to send.
  Future<void> put(String path, Uint8List bytes) async {
    final stamp = _clock().microsecondsSinceEpoch.toString().padLeft(20, '0');
    final id = '$dir$stamp-${(_seq++).toString().padLeft(6, '0')}';
    await store.write('$id.body', bytes);
    // The path goes last: an item only exists once both parts do.
    await store.write('$id$_pathSuffix', Uint8List.fromList(utf8.encode(path)));
  }

  /// How many items are waiting.
  Future<int> pending() async =>
      (await store.list(dir)).where((n) => n.endsWith(_pathSuffix)).length;

  /// Sends what is waiting, oldest first; returns how many still wait.
  ///
  /// One run at a time. A call while one runs gets a follow-up run (shared
  /// by every such call): the running one listed the items before anything
  /// queued since, so answering with its count would call a photo still on
  /// the phone sent.
  Future<int> flush() {
    if (_followUp case final next?) return next;
    final running = _flushing;
    if (running == null) return _start();
    return _followUp ??= running
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) {
          _followUp = null;
          return _start();
        });
  }

  Future<int> _start() =>
      _flushing = _flush().whenComplete(() => _flushing = null);

  Future<int> _flush() async {
    final items = [
      for (final n in await store.list(dir))
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
          onSent?.call(path, error);
          return items.length - i;
        }
        onSent?.call(path, null);
      }
      await store.delete(name);
      await store.delete('$id.body');
    }
    lastError = null;
    return 0;
  }
}
