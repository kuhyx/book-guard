import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Base URL every fake share answers on.
const fakeShareUrl = 'https://dufs.test';

/// An in-memory dufs share behind a [MockClient].
///
/// Files live in [files], keyed by their decoded share-relative path. When
/// [answer] is set, every request file PUT under `Reading/requests/` gets a
/// response file written next to it, the way the PC would.
class FakeShare {
  /// Files on the share.
  final Map<String, Uint8List> files = {};

  /// Every request the client sent, in order.
  final List<http.Request> requests = [];

  /// Builds the PC's answer to a request payload; null = the PC is off.
  Map<String, Object?>? Function(Map<String, dynamic> request)? answer;

  /// When set, every call answers with this status instead.
  int? forceStatus;

  /// The HTTP client to hand to [DavClient].
  late final MockClient client = MockClient(_handle);

  /// A [DavClient] over this share.
  DavClient dav({String user = '', String password = ''}) => DavClient(
    baseUrl: fakeShareUrl,
    user: user,
    password: password,
    client: client,
  );

  /// Puts a text file on the share.
  void putText(String path, String text) =>
      files[path] = Uint8List.fromList(utf8.encode(text));

  /// A file on the share as text, or null.
  String? text(String path) {
    final bytes = files[path];
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final forced = forceStatus;
    if (forced != null) return http.Response('', forced);
    final path = request.url.pathSegments.join('/');
    switch (request.method) {
      case 'GET':
        final bytes = files[path];
        return bytes == null
            ? http.Response('', 404)
            : http.Response.bytes(bytes, 200);
      case 'PUT':
        files[path] = request.bodyBytes;
        _maybeAnswer(path, request.body);
        return http.Response('', 201);
      case 'DELETE':
        return files.remove(path) == null
            ? http.Response('', 404)
            : http.Response('', 204);
    }
    return http.Response('', 405);
  }

  void _maybeAnswer(String path, String body) {
    final build = answer;
    if (build == null || !path.startsWith('Reading/requests/')) return;
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final response = build(payload);
    if (response == null) return;
    putText('Reading/responses/${payload['id']}.json', jsonEncode(response));
  }
}
