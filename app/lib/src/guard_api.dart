import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/error_log.dart';
import 'package:book_guard_app/src/guard_response.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/outbox.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/photo_reports.dart';

export 'package:book_guard_app/src/guard_response.dart';
export 'package:book_guard_app/src/photo_reports.dart';

/// book-guard's file protocol over the dufs share (see the Python side's
/// `_requests.py`): read `state.json`, drop request files, poll responses,
/// upload photos and book files. Every path is under `Reading/`, the only
/// folder the app's dufs login can reach.
///
/// Offline first: photos, their sidecar notes, summaries and error entries
/// go through the [outbox] on the device and reach the PC whenever it
/// answers; the last snapshot is kept in [store] so the app still shows
/// where the reading stands with no network at all.
class GuardApi {
  /// Creates an API over [dav]; [store] keeps the outbox, the journal and
  /// the last snapshot (memory if not given).
  new(
    this.dav, {
    Random? random,
    Duration? pollEvery,
    Duration? timeout,
    LocalStore? store,
    String host = 'phone',
  }) : _random = random ?? Random.secure(),
       _pollEvery = pollEvery ?? const Duration(seconds: 2),
       _timeout = timeout ?? const Duration(minutes: 5),
       store = store ?? MemoryStore() {
    outbox = Outbox(this.store, dav);
    errors = ErrorLog(this.store, outbox, host: host);
    journal = Journal(this.store);
  }

  /// The share.
  final DavClient dav;

  /// The device's own storage.
  final LocalStore store;

  /// Everything waiting to go to the PC.
  late final Outbox outbox;

  /// The device's failures, mirrored to the PC's `errors.jsonl`.
  late final ErrorLog errors;

  /// Every photo taken here.
  late final Journal journal;

  final Random _random;
  final Duration _pollEvery;
  final Duration _timeout;

  static const _root = 'Reading';
  static const _stateFile = 'state.json';
  static const _pending = 'pending/';

  /// The latest snapshot, or null before the PC ever wrote one. Kept on
  /// the device for [cachedState].
  Future<GuardState?> fetchState() async {
    final text = await dav.getText('$_root/state.json');
    if (text == null) return null;
    final state = GuardState.fromJson(jsonDecode(text) as Map<String, dynamic>);
    await store.write(_stateFile, Uint8List.fromList(utf8.encode(text)));
    return state;
  }

  /// Sends what the outbox holds; returns how many items still wait.
  Future<int> flush() => outbox.flush();

  /// The last snapshot fetched, for when the PC cannot be reached.
  Future<GuardState?> cachedState() async {
    final raw = await store.read(_stateFile);
    if (raw == null) return null;
    return GuardState.fromJson(
      jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
    );
  }

  /// A fresh request id the PC accepts (`[A-Za-z0-9_-]{8,64}`).
  String newId() =>
      List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();

  /// Sends one request and waits for the PC's answer -- for lookups and
  /// edits, which mean nothing offline.
  ///
  /// Grading a summary takes the PC ~10-30 s; a PC that is off answers when
  /// it next boots, so a timeout is "not yet", not "no".
  Future<GuardResponse> send(String type, Map<String, Object?> body) async {
    final id = newId();
    final payload = {'id': id, 'type': type, ...body};
    await dav.put(
      '$_root/requests/$id.json',
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
    return await _await(id) ?? _notYet;
  }

  static const _notYet = GuardResponse(
    ok: false,
    message: 'The PC has not answered yet - it will when it is on.',
  );

  /// Queues one request on the device and, if the PC is reachable, waits
  /// for its answer. Offline it stays queued; the answer is picked up by
  /// [collectAnswers] later. [what] names it for that later message.
  Future<GuardResponse> sendQueued(
    String type,
    Map<String, Object?> body,
    String what,
  ) async {
    final id = newId();
    final payload = {'id': id, 'type': type, ...body};
    await outbox.put(
      'requests/$id.json',
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
    await store.write('$_pending$id', Uint8List.fromList(utf8.encode(what)));
    if (await flush() > 0) {
      return const GuardResponse(
        ok: true,
        message:
            'Saved on the phone - it goes to the PC (and is graded) as soon '
            'as the PC is reachable.',
      );
    }
    final answer = await _await(id);
    if (answer == null) return _notYet;
    await store.delete('$_pending$id');
    return answer;
  }

  /// Answers to queued requests that arrived since; each is returned once.
  Future<List<LateAnswer>> collectAnswers() async {
    final found = <LateAnswer>[];
    for (final name in await store.list(_pending)) {
      final id = name.substring(_pending.length);
      final response = await _take(id);
      if (response == null) continue;
      final what = utf8.decode(await store.read(name) ?? const []);
      await store.delete(name);
      found.add((what: what, response: response));
    }
    return found;
  }

  Future<GuardResponse?> _await(String id) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollEvery);
      final response = await _take(id);
      if (response != null) return response;
    }
    return null;
  }

  Future<GuardResponse?> _take(String id) async {
    final text = await dav.getText('$_root/responses/$id.json');
    if (text == null) return null;
    await dav.delete('$_root/responses/$id.json');
    final json = jsonDecode(text) as Map<String, dynamic>;
    return GuardResponse(
      ok: json['ok'] == true,
      message: '${json['message'] ?? ''}',
      passed: json['passed'] as bool?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// Stores a photo on the device and queues it (sidecar note first) for
  /// the PC's inbox; [page] and [box] are what the phone read. Returns the
  /// name it is uploaded under. Call [outbox] `flush` to send.
  Future<String> queuePhoto(
    String label,
    String fileName,
    Uint8List bytes, {
    int? page,
    Box? box,
    DateTime? takenAt,
  }) async {
    final name = safeName('${label}_$fileName');
    if (page != null || box != null) {
      final note = {
        'page': ?page,
        if (box != null) 'box': [box.left, box.top, box.right, box.bottom],
      };
      await outbox.put(
        'inbox/$name.json',
        Uint8List.fromList(utf8.encode(jsonEncode(note))),
      );
    }
    await outbox.put('inbox/$name', bytes);
    await store.write('photos/$name', bytes);
    await journal.add(
      JournalEntry(
        name: name,
        label: label,
        sha: photoSha(bytes),
        takenAt: takenAt ?? DateTime.now(),
        page: page,
      ),
    );
    await prunePhotos();
    return name;
  }

  /// Queues a photo that is not session evidence (a contents page) and
  /// tries to send it; returns the name it goes under and whether it went.
  Future<(String, bool)> uploadPhoto(String name, Uint8List bytes) async {
    final safe = safeName(name);
    await outbox.put('inbox/$safe', bytes);
    return (safe, await flush() == 0);
  }

  /// A file under `Reading/` (a thumbnail, a photo), or null.
  Future<Uint8List?> fetchBytes(String path) => dav.getBytes('$_root/$path');

  /// Polls the snapshot until [test] holds, or gives up after the timeout.
  Future<GuardState?> waitFor(bool Function(GuardState state) test) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollEvery);
      final state = await fetchState();
      if (state != null && test(state)) return state;
    }
    return null;
  }

  /// The PC's reading of the photo uploaded as [name]; null if it has not
  /// read it before the timeout (the PC may be off).
  Future<PhotoInfo?> waitForPhoto(String name) async {
    final state = await waitFor((s) => s.photos.any((p) => p.name == name));
    return state?.photos.firstWhere((p) => p.name == name);
  }

  /// Uploads an ebook file for the current book.
  Future<void> uploadBook(String name, Uint8List bytes) =>
      dav.put('$_root/books/${safeName(name)}', bytes);
}
