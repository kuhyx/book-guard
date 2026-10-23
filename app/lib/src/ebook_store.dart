import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/ebook_map.dart';
import 'package:book_guard_app/src/ebook_models.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/responses.dart';
import 'package:crypto/crypto.dart';

export 'package:book_guard_app/src/ebook_map.dart';
export 'package:book_guard_app/src/ebook_models.dart';

/// The in-app reader's device side: the downloaded text and map, where the
/// reader is, a running session, and finished ones waiting for the PC.
///
/// Everything lives in the app's own store (its support folder on the
/// phone), so reading works with the PC and the network both gone; the
/// finished session goes to the PC through the outbox as an
/// `ebook_session` request (`book_guard/_ebook_sessions.py`).
extension EbookStore on GuardApi {
  static const _dir = 'ebook/';
  static const _done = 'ebook/sessions/';
  static const _pending = 'pending/';

  /// Default reading font size.
  static const defaultFontSize = 18.0;

  Uint8List _bytes(Object? json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  Future<Object?> _json(String name) async {
    final raw = await store.read(name);
    if (raw == null) return null;
    try {
      return jsonDecode(utf8.decode(raw));
    } on FormatException {
      return null;
    }
  }

  /// The ebook kept on the device for [isbn], or null.
  Future<Ebook?> cachedEbook(String isbn) async {
    final map = EbookMap.fromJson(await _json('$_dir$isbn.map.json'));
    final text = await store.read('$_dir$isbn.txt');
    if (map == null || text == null) return null;
    return Ebook(map, utf8.decode(text));
  }

  /// Fetches [ref]'s map, and its text unless the kept one is the same;
  /// keeps both. Offline, or on anything wrong, the kept copy (or null).
  Future<Ebook?> syncEbook(String isbn, EbookRef ref) async {
    final kept = await cachedEbook(isbn);
    try {
      final raw = await fetchBytes(ref.map);
      final map = raw == null ? null : EbookMap.fromJson(_decode(raw));
      if (map == null) return kept;
      var text = kept?.text;
      if (kept == null || kept.map.textSha != map.textSha) {
        final bytes = await fetchBytes(map.textPath);
        if (bytes == null || sha256.convert(bytes).toString() != map.textSha) {
          return kept;
        }
        text = utf8.decode(bytes);
        await store.write('$_dir$isbn.txt', bytes);
      }
      await store.write('$_dir$isbn.map.json', raw!);
      return Ebook(map, text!);
    } on Exception {
      return kept;
    }
  }

  Object? _decode(Uint8List raw) {
    try {
      return jsonDecode(utf8.decode(raw));
    } on FormatException {
      return null;
    }
  }

  /// Where the reader was in [isbn], or null.
  Future<int?> readingPosition(String isbn) async {
    final raw = await _json('$_dir$isbn.pos');
    return raw is int ? raw : null;
  }

  /// Remembers where the reader is in [isbn].
  Future<void> savePosition(String isbn, int offset) =>
      store.write('$_dir$isbn.pos', _bytes(offset));

  /// The reading font size.
  Future<double> fontSize() async {
    final raw = await _json('${_dir}font');
    return raw is num ? raw.toDouble() : defaultFontSize;
  }

  /// Remembers the reading font size.
  Future<void> saveFontSize(double size) =>
      store.write('${_dir}font', _bytes(size));

  /// The running in-app session in [isbn], if one was started.
  Future<ReadingStart?> readingStart(String isbn) async =>
      ReadingStart.fromJson(await _json('$_dir$isbn.start.json'));

  /// Keeps [start] at once: the tap is the session's clock.
  Future<void> startReading(ReadingStart start) =>
      store.write('$_dir${start.isbn}.start.json', _bytes(start.toJson()));

  /// Forgets the running session in [isbn] (nothing is sent).
  Future<void> cancelReading(String isbn) =>
      store.delete('$_dir$isbn.start.json');

  /// Stops [start] at [endOffset] and [now]: keeps the session for its
  /// summary and queues it for the PC. The PC computes the credited pages
  /// with its own map; [map] only names them here.
  Future<AppSession> stopReading(
    ReadingStart start,
    int endOffset,
    EbookMap map,
    DateTime now,
  ) async {
    final requestId = newId();
    final done = AppSession(
      key: start.id,
      requestId: requestId,
      startPage: map.pageAt(start.offset),
      endPage: map.pageAt(endOffset),
      startedAt: start.startedAt,
      endedAt: now,
    );
    await store.write('$_done${start.id}.json', _bytes(done.toJson()));
    final request = {
      'id': requestId,
      'type': 'ebook_session',
      'session': start.id,
      'isbn': start.isbn,
      'start_offset': start.offset,
      'end_offset': endOffset,
      'started_at': start.startedAt.toUtc().toIso8601String(),
      'ended_at': now.toUtc().toIso8601String(),
      'text_sha': start.textSha,
    };
    await outbox.put('requests/$requestId.json', _bytes(request));
    await store.write(
      '$_pending$requestId',
      Uint8List.fromList(utf8.encode('In-app reading ${done.info.span}')),
    );
    await cancelReading(start.isbn);
    await flush();
    return done;
  }

  /// Sessions stopped here that the PC may not list yet.
  Future<List<AppSession>> appSessions() async => [
    for (final name in await store.list(_done))
      if (await _json(name) case final Map<String, dynamic> json)
        AppSession.fromJson(json),
  ];

  /// Drops [key] from [appSessions] (the PC lists or refused it).
  Future<void> forgetAppSession(String key) => store.delete('$_done$key.json');

  /// Whether the PC refused [session] (its answer has arrived).
  Future<bool> refused(AppSession session) async =>
      await store.read('$refusedPrefix${session.requestId}') != null;
}
