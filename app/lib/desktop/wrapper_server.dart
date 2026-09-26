/// The desktop half of the app: serves the web build and proxies WebDAV.
///
/// The browser never holds the dufs login. `/dav/...` is forwarded to the
/// local dufs (127.0.0.1:5000) with the `bookguard` login from
/// `~/.config/dufs/logins/bookguard.env` attached here, re-read per request
/// so rotating the login needs no restart. Bound to loopback only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Fixed on purpose: a different port is a different browser origin.
const kWrapperPort = 8773;

/// Where the local dufs listens (its config binds 127.0.0.1:5000).
final Uri kLocalDufs = Uri.parse('http://127.0.0.1:5000');

/// The login `add_dufs_login.sh bookguard /Reading rw` writes.
String loginEnvPath(String home) =>
    p.join(home, '.config', 'dufs', 'logins', 'bookguard.env');

/// `KEY=value` lines of an env file, or empty when it is missing.
Map<String, String> readEnv(File file) {
  if (!file.existsSync()) return const {};
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final eq = line.indexOf('=');
    if (eq <= 0 || line.startsWith('#')) continue;
    values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return values;
}

/// Serves [webRoot] and proxies `/dav` to [dufs].
class WrapperServer {
  /// Creates a server.
  new({
    required this.webRoot,
    required this.loginEnv,
    Uri? dufs,
    HttpClient? client,
  }) : dufs = dufs ?? kLocalDufs,
       _client = client ?? HttpClient();

  /// The Flutter web build.
  final String webRoot;

  /// The dufs login env file.
  final File loginEnv;

  /// The dufs server to forward to.
  final Uri dufs;

  final HttpClient _client;
  HttpServer? _server;

  /// Starts listening on loopback [port] (0 = any, for tests).
  Future<int> start({int port = kWrapperPort}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  /// Stops listening.
  Future<void> close() async => await _server?.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/dav' || path.startsWith('/dav/')) {
        await _proxy(request, path.substring('/dav'.length));
      } else {
        await _static(request, path);
      }
    } on Exception catch (error) {
      stderr.writeln('book-guard desktop: ${request.uri.path}: $error');
      request.response.statusCode = HttpStatus.badGateway;
    } finally {
      await request.response.close();
    }
  }

  Future<void> _proxy(HttpRequest request, String rest) async {
    final env = readEnv(loginEnv);
    final user = env['DUFS_USER'] ?? '';
    final password = env['DUFS_PASSWORD'] ?? '';
    if (user.isEmpty || password.isEmpty) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('no dufs login at ${loginEnv.path}');
      return;
    }
    final target = dufs.replace(
      path: rest.isEmpty ? '/' : rest,
      query: request.uri.query.isEmpty ? null : request.uri.query,
    );
    final outgoing = await _client.openUrl(request.method, target);
    outgoing.headers
      ..set(HttpHeaders.authorizationHeader, _basic(user, password))
      ..contentType = request.headers.contentType;
    await outgoing.addStream(request);
    final answer = await outgoing.close();
    request.response.statusCode = answer.statusCode;
    final type = answer.headers.contentType;
    if (type != null) request.response.headers.contentType = type;
    await request.response.addStream(answer);
  }

  static String _basic(String user, String password) =>
      'Basic ${base64Encode(utf8.encode('$user:$password'))}';

  Future<void> _static(HttpRequest request, String path) async {
    final relative = path == '/' ? 'index.html' : path.substring(1);
    final resolved = p.normalize(p.join(webRoot, relative));
    if (!p.isWithin(webRoot, resolved)) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    final file = File(resolved);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = contentTypeFor(resolved);
    await request.response.addStream(file.openRead());
  }

  /// Content type for [filePath]. CanvasKit refuses a `.wasm` served as
  /// anything but `application/wasm`, and the app then renders nothing.
  static ContentType contentTypeFor(String filePath) =>
      switch (p.extension(filePath).toLowerCase()) {
        '.html' => ContentType.html,
        '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
        '.json' => ContentType.json,
        '.wasm' => ContentType('application', 'wasm'),
        '.css' => ContentType('text', 'css', charset: 'utf-8'),
        '.png' => ContentType('image', 'png'),
        '.svg' => ContentType('image', 'svg+xml'),
        '.ttf' => ContentType('font', 'ttf'),
        '.otf' => ContentType('font', 'otf'),
        '.woff2' => ContentType('font', 'woff2'),
        _ => ContentType.binary,
      };
}
