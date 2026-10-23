import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/outbox.dart';

/// The app's half of `Reading/logs/errors.jsonl`: every failure the person
/// sees is also kept here and sent to the PC, which merges it into the one
/// shared log -- one JSON object per line, for a human or a later Claude
/// session to read without anyone retyping an error message.
class ErrorLog {
  /// Creates a log over [store], sending through [outbox] as [host].
  new(
    this.store,
    this.outbox, {
    required this.host,
    DateTime Function()? clock,
    Random? random,
    Outbox? events,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       events = events ?? outbox;

  /// The local copy.
  final LocalStore store;

  /// Sends entries to the PC.
  final Outbox outbox;

  /// Sends lifecycle events to the PC: its own queue, so they never count
  /// as items "waiting on the phone".
  final Outbox events;

  final _serial = Serial();

  /// `phone` or `desktop`.
  final String host;

  final DateTime Function() _clock;
  final Random _random;

  static const _file = 'errors.jsonl';

  /// Entries kept on the device.
  static const keep = 200;

  /// Records one failure: [stage] is where (`photo`, `upload`, `reader`,
  /// `summary`...), [error] what, [detail] anything that helps.
  Future<void> log(
    String stage,
    String error, [
    Map<String, Object?> detail = const {},
  ]) async {
    final line = jsonEncode({
      'at': _clock().toIso8601String(),
      'host': host,
      'stage': stage,
      'error': error,
      ...detail,
    });
    // Queued for the PC first: a failing local copy must not lose it.
    await outbox.put(_name(), _bytes(line));
    await _serial.run(() async {
      final lines = [...await _lines(), line];
      final kept = lines.length > keep
          ? lines.sublist(lines.length - keep)
          : lines;
      await store.write(_file, _bytes('${kept.join('\n')}\n'));
    });
  }

  /// Records one step of the photo pipeline (`camera`, `captured`,
  /// `queued`, `uploaded`...) for the PC's `logs/phone-events.jsonl`.
  /// Never throws: a log must not cost a photo.
  Future<void> event(
    String stage,
    String what, [
    Map<String, Object?> detail = const {},
  ]) async {
    try {
      final line = jsonEncode({
        'at': _clock().toIso8601String(),
        'host': host,
        'level': 'event',
        'stage': stage,
        'event': what,
        ...detail,
      });
      await events.put(_name(), _bytes(line));
    } on Object catch (_) {
      // Nowhere left to report it; the photo goes on regardless.
    }
  }

  String _name() {
    final id = List.generate(12, (_) => _random.nextInt(16).toRadixString(16));
    return 'logs/phone/${id.join()}.json';
  }

  Future<List<String>> _lines() async {
    final raw = await store.read(_file);
    return raw == null ? [] : const LineSplitter().convert(utf8.decode(raw));
  }

  /// What "Copy diagnostics" puts on the clipboard: the newest entries and
  /// what is still waiting to be sent.
  Future<String> diagnostics({int last = 30}) async {
    final lines = await _lines();
    final tail = lines.length > last
        ? lines.sublist(lines.length - last)
        : lines;
    return [
      'book-guard $host diagnostics, ${_clock().toIso8601String()}',
      'waiting to send: ${await outbox.pending()}',
      if (outbox.lastError case final error?) 'last send failed: $error',
      ...tail,
    ].join('\n');
  }

  static Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));
}
