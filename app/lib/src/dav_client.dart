import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when the dufs share answers with anything but success.
class DavException implements Exception {
  /// Creates an error for [status] on [path].
  const new(this.path, this.status, [this.detail = '']);

  /// The share-relative path that failed.
  final String path;

  /// HTTP status (0 when the server was unreachable).
  final int status;

  /// Extra context for the human.
  final String detail;

  @override
  String toString() => status == 401 || status == 403
      ? 'The dufs login was refused ($status) - check Settings.'
      : 'dufs $path failed ($status) $detail'.trim();
}

/// The minimal WebDAV client book-guard needs: GET, PUT, DELETE.
///
/// On the phone [baseUrl] is the public dufs URL and [user]/[password] the
/// login scoped to `/Reading`. On the desktop the local wrapper proxies
/// `/dav` to dufs and adds the login itself, so both are empty there and no
/// credential ever reaches the browser.
class DavClient {
  /// Creates a client for [baseUrl].
  new({
    required this.baseUrl,
    this.user = '',
    this.password = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Share root, without a trailing slash.
  final String baseUrl;

  /// Basic-auth user; empty when the wrapper authenticates.
  final String user;

  /// Basic-auth password.
  final String password;

  final http.Client _client;

  Map<String, String> get _headers => user.isEmpty
      ? const {}
      : {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$user:$password'))}',
        };

  Uri _uri(String path) => Uri.parse(
    '$baseUrl/${path.split('/').map(Uri.encodeComponent).join('/')}',
  );

  /// The file at [path] as text, or null when it does not exist.
  Future<String?> getText(String path) async {
    final response = await _send(
      () => _client.get(_uri(path), headers: _headers),
      path,
    );
    if (response.statusCode == 404) return null;
    _check(path, response);
    return utf8.decode(response.bodyBytes);
  }

  /// The file at [path] as bytes, or null when it does not exist.
  Future<Uint8List?> getBytes(String path) async {
    final response = await _send(
      () => _client.get(_uri(path), headers: _headers),
      path,
    );
    if (response.statusCode == 404) return null;
    _check(path, response);
    return response.bodyBytes;
  }

  /// Uploads [bytes] to [path], creating or replacing the file.
  Future<void> put(String path, Uint8List bytes) async {
    final response = await _send(
      () => _client.put(_uri(path), headers: _headers, body: bytes),
      path,
    );
    _check(path, response);
  }

  /// Deletes [path]; a missing file is not an error.
  Future<void> delete(String path) async {
    final response = await _send(
      () => _client.delete(_uri(path), headers: _headers),
      path,
    );
    if (response.statusCode != 404) _check(path, response);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() call,
    String path,
  ) async {
    try {
      return await call();
    } on Exception catch (error) {
      throw DavException(path, 0, 'unreachable: $error');
    }
  }

  void _check(String path, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DavException(path, response.statusCode);
    }
  }
}
