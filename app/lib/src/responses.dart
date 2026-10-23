import 'dart:convert';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_response.dart';

/// Where `GuardApi.collectAnswers` marks a queued request the PC refused
/// (`refused/<id>`), so whatever queued it -- an in-app session -- can tell.
const refusedPrefix = 'refused/';

/// The PC's answers in `Reading/responses/`, one file per request id, each
/// taken (read and deleted) once.
class Responses {
  /// Creates the reader over [dav].
  new(this.dav, {required this.pollEvery, required this.timeout});

  /// The share.
  final DavClient dav;

  /// How often [wait] looks.
  final Duration pollEvery;

  /// How long [wait] looks before giving up.
  final Duration timeout;

  static const _dir = 'Reading/responses';

  /// Polls for the answer to [id]; null if none came before the timeout.
  Future<GuardResponse?> wait(String id) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      final response = await take(id);
      if (response != null) return response;
    }
    return null;
  }

  /// The answer to [id] if it is there, removed from the share; or null.
  Future<GuardResponse?> take(String id) async {
    final text = await dav.getText('$_dir/$id.json');
    if (text == null) return null;
    await dav.delete('$_dir/$id.json');
    final json = jsonDecode(text) as Map<String, dynamic>;
    return GuardResponse(
      ok: json['ok'] == true,
      message: '${json['message'] ?? ''}',
      passed: json['passed'] as bool?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}
