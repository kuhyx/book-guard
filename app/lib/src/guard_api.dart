import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_state.dart';

/// The PC's answer to one request file.
class GuardResponse {
  /// Creates a response.
  const new({required this.ok, required this.message, this.passed, this.data});

  /// Whether the request was carried out.
  final bool ok;

  /// A line for the human.
  final String message;

  /// For summaries: whether the session was credited.
  final bool? passed;

  /// For lookups: the fields found.
  final Map<String, dynamic>? data;
}

/// book-guard's file protocol over the dufs share (see the Python side's
/// `_requests.py`): read `state.json`, drop request files, poll responses,
/// upload photos and book files. Every path is under `Reading/`, the only
/// folder the app's dufs login can reach.
class GuardApi {
  /// Creates an API over [dav].
  new(this.dav, {Random? random, Duration? pollEvery, Duration? timeout})
    : _random = random ?? Random.secure(),
      _pollEvery = pollEvery ?? const Duration(seconds: 2),
      _timeout = timeout ?? const Duration(minutes: 5);

  /// The share.
  final DavClient dav;
  final Random _random;
  final Duration _pollEvery;
  final Duration _timeout;

  static const _root = 'Reading';

  /// The latest snapshot, or null before the PC ever wrote one.
  Future<GuardState?> fetchState() async {
    final text = await dav.getText('$_root/state.json');
    if (text == null) return null;
    return GuardState.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  /// A fresh request id the PC accepts (`[A-Za-z0-9_-]{8,64}`).
  String newId() =>
      List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();

  /// Sends one request and waits for the PC's answer.
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
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollEvery);
      final text = await dav.getText('$_root/responses/$id.json');
      if (text == null) continue;
      await dav.delete('$_root/responses/$id.json');
      final json = jsonDecode(text) as Map<String, dynamic>;
      return GuardResponse(
        ok: json['ok'] == true,
        message: '${json['message'] ?? ''}',
        passed: json['passed'] as bool?,
        data: json['data'] as Map<String, dynamic>?,
      );
    }
    return const GuardResponse(
      ok: false,
      message: 'The PC has not answered yet - it will when it is on.',
    );
  }

  /// Uploads a photo; [name] keeps the camera's file name. Returns the name
  /// it landed under, to find the PC's reading with [waitForPhoto].
  Future<String> uploadPhoto(String name, Uint8List bytes) async {
    final safe = _safe(name);
    await dav.put('$_root/inbox/$safe', bytes);
    return safe;
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
      dav.put('$_root/books/${_safe(name)}', bytes);

  String _safe(String name) {
    final base = name.split(RegExp(r'[\\/]')).last;
    final cleaned = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? '${newId()}.bin' : cleaned;
  }
}
