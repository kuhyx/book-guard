import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/desktop/wrapper_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// What the fake dufs saw of one forwarded request.
typedef Seen = ({
  String method,
  String path,
  String query,
  String? auth,
  String? type,
  List<int> body,
});

void main() {
  late Directory dir;
  late File loginEnv;
  late HttpServer dufs;
  late WrapperServer server;
  late int port;
  final seen = <Seen>[];
  final client = HttpClient();

  setUp(() async {
    seen.clear();
    dir = Directory.systemTemp.createTempSync('bg_proxy');
    loginEnv = File(p.join(dir.path, 'bookguard.env'))
      ..writeAsStringSync('DUFS_USER=bookguard\nDUFS_PASSWORD=pw\n');
    dufs = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        seen.add((
          method: request.method,
          path: request.uri.path,
          query: request.uri.query,
          auth: request.headers.value(HttpHeaders.authorizationHeader),
          type: request.headers.contentType?.mimeType,
          body: body,
        ));
        final response = request.response;
        if (request.method == 'GET') {
          response.headers.contentType = ContentType.json;
          response.write('{"ok":true}');
        } else {
          response
            ..statusCode = HttpStatus.created
            ..headers.removeAll(HttpHeaders.contentTypeHeader);
        }
        await response.close();
      });
    server = WrapperServer(
      webRoot: dir.path,
      loginEnv: loginEnv,
      dufs: Uri.parse('http://127.0.0.1:${dufs.port}'),
      client: HttpClient(),
    );
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await server.close();
    await dufs.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<(int, String?, String)> call(
    String method,
    String path, {
    List<int>? body,
    ContentType? type,
  }) async {
    final request = await client.open(method, '127.0.0.1', port, path);
    if (type != null) request.headers.contentType = type;
    if (body != null) request.add(body);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (response.statusCode, response.headers.contentType?.mimeType, text);
  }

  test('GET is forwarded with the login and the query', () async {
    final (status, type, text) = await call(
      'GET',
      '/dav/Reading/state.json?x=1',
    );
    expect((status, type, text), (200, 'application/json', '{"ok":true}'));
    final request = seen.single;
    expect(request.method, 'GET');
    expect(request.path, '/Reading/state.json');
    expect(request.query, 'x=1');
    expect(request.auth, 'Basic ${base64Encode(utf8.encode('bookguard:pw'))}');
  });

  test('PUT streams the body and its content type through', () async {
    final (status, _, _) = await call(
      'PUT',
      '/dav/Reading/inbox/a.jpg',
      body: [1, 2, 3],
      type: ContentType('image', 'jpeg'),
    );
    expect(status, HttpStatus.created);
    final request = seen.single;
    expect(request.method, 'PUT');
    expect(request.body, [1, 2, 3]);
    expect(request.type, 'image/jpeg');
    expect(request.query, '');
  });

  test('bare /dav is the share root', () async {
    await call('GET', '/dav');
    expect(seen.single.path, '/');
  });

  test('the login is re-read per request', () async {
    await call('GET', '/dav/a');
    loginEnv.writeAsStringSync('DUFS_USER=other\nDUFS_PASSWORD=new\n');
    await call('GET', '/dav/a');
    expect(seen.last.auth, 'Basic ${base64Encode(utf8.encode('other:new'))}');
  });

  test('no login means 503 and nothing forwarded', () async {
    loginEnv.writeAsStringSync('DUFS_USER=bookguard\n');
    final (status, _, text) = await call('GET', '/dav/a');
    expect(status, HttpStatus.serviceUnavailable);
    expect(text, contains('no dufs login at ${loginEnv.path}'));
    loginEnv.deleteSync();
    expect((await call('GET', '/dav/a')).$1, HttpStatus.serviceUnavailable);
    expect(seen, isEmpty);
  });

  test('an unreachable dufs is 502', () async {
    final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = gone.port;
    await gone.close(force: true);
    final orphan = WrapperServer(
      webRoot: dir.path,
      loginEnv: loginEnv,
      dufs: Uri.parse('http://127.0.0.1:$deadPort'),
    );
    final orphanPort = await orphan.start(port: 0);
    addTearDown(orphan.close);
    final request = await client.get('127.0.0.1', orphanPort, '/dav/x');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.badGateway);
  });
}
