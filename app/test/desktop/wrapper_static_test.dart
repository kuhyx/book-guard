import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/desktop/wrapper_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sends [path] verbatim over a raw socket, so no client normalises it.
Future<String> rawGet(int port, String path) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(
    'GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
  );
  await socket.flush();
  final reply = await utf8.decoder.bind(socket).join();
  await socket.close();
  return reply;
}

void main() {
  test('loginEnvPath is the add_dufs_login.sh file', () {
    expect(loginEnvPath('/h'), '/h/.config/dufs/logins/bookguard.env');
    expect(kWrapperPort, 8773);
    expect(kLocalDufs.toString(), 'http://127.0.0.1:5000');
  });

  group('readEnv', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bg_env'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('is empty when the file is missing', () {
      expect(readEnv(File(p.join(dir.path, 'none.env'))), isEmpty);
    });

    test('reads KEY=value lines and skips the rest', () {
      final file = File(p.join(dir.path, 'x.env'))
        ..writeAsStringSync(
          '# comment=yes\n'
          'DUFS_USER = bookguard \n'
          'DUFS_PASSWORD=a=b\n'
          '=novalue\n'
          'garbage\n',
        );
      expect(readEnv(file), {'DUFS_USER': 'bookguard', 'DUFS_PASSWORD': 'a=b'});
    });
  });

  test('contentTypeFor covers every served kind', () {
    String type(String name) => WrapperServer.contentTypeFor(name).mimeType;
    expect(type('index.HTML'), 'text/html');
    expect(type('main.dart.js'), 'text/javascript');
    expect(type('x.mjs'), 'text/javascript');
    expect(type('manifest.json'), 'application/json');
    expect(type('canvaskit.wasm'), 'application/wasm');
    expect(type('a.css'), 'text/css');
    expect(type('icon.png'), 'image/png');
    expect(type('logo.svg'), 'image/svg+xml');
    expect(type('f.ttf'), 'font/ttf');
    expect(type('f.otf'), 'font/otf');
    expect(type('f.woff2'), 'font/woff2');
    expect(type('NOTICES'), 'application/octet-stream');
  });

  group('static files', () {
    late Directory dir;
    late WrapperServer server;
    late int port;
    final client = HttpClient();

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('bg_web');
      final web = Directory(p.join(dir.path, 'web'))..createSync();
      File(p.join(web.path, 'index.html')).writeAsStringSync('<p>hi</p>');
      Directory(p.join(web.path, 'js')).createSync();
      File(p.join(web.path, 'js', 'main.js')).writeAsStringSync('go()');
      File(p.join(dir.path, 'secret.txt')).writeAsStringSync('nope');
      server = WrapperServer(
        webRoot: web.path,
        loginEnv: File(p.join(dir.path, 'login.env')),
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.close();
      dir.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> get(String path) async {
      final request = await client.get('127.0.0.1', port, path);
      return await request.close();
    }

    test('/ serves index.html as HTML', () async {
      final response = await get('/');
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(await utf8.decoder.bind(response).join(), '<p>hi</p>');
    });

    test('nested files get their content type', () async {
      final response = await get('/js/main.js');
      expect(response.headers.contentType?.mimeType, 'text/javascript');
      expect(await utf8.decoder.bind(response).join(), 'go()');
    });

    test('a missing file is 404', () async {
      final response = await get('/nope.js');
      expect(response.statusCode, 404);
      await response.drain<void>();
    });

    test('nothing outside the web root is served', () async {
      // Dot segments are already folded away by the URI parser...
      for (final path in ['/../secret.txt', '/%2e%2e/secret.txt']) {
        final reply = await rawGet(port, path);
        expect(reply, startsWith('HTTP/1.1 404'), reason: path);
      }
      // ...but an authority-form target leaves an absolute path, which
      // p.join would happily resolve outside the root.
      final reply = await rawGet(port, '//x/${dir.path}/secret.txt');
      expect(reply, startsWith('HTTP/1.1 403'));
      expect(reply, isNot(contains('nope')));
    });

    test('closing twice and before start is harmless', () async {
      await server.close();
      final idle = WrapperServer(webRoot: dir.path, loginEnv: File('x'));
      await idle.close();
      expect(idle.dufs, kLocalDufs);
    });
  });
}
