import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_share.dart';

void main() {
  group('DavException', () {
    test('names a refused login for 401 and 403', () {
      for (final status in [401, 403]) {
        expect(
          DavException('a', status).toString(),
          'The dufs login was refused ($status) - check Settings.',
        );
      }
    });

    test('names the path, status and detail otherwise', () {
      expect(
        const DavException('x.json', 500).toString(),
        'dufs x.json failed (500)',
      );
      expect(
        const DavException('x.json', 0, 'unreachable').toString(),
        'dufs x.json failed (0) unreachable',
      );
      const error = DavException('p', 7, 'd');
      expect((error.path, error.status, error.detail), ('p', 7, 'd'));
    });
  });

  group('DavClient', () {
    late FakeShare share;

    setUp(() => share = FakeShare());

    test('sends basic auth only when a user is set', () async {
      await share.dav(user: 'bookguard', password: 's3cret').getText('a');
      await share.dav().getText('a');
      final expected = 'Basic ${base64Encode(utf8.encode('bookguard:s3cret'))}';
      expect(share.requests[0].headers['Authorization'], expected);
      expect(share.requests[1].headers.containsKey('Authorization'), isFalse);
    });

    test('percent-encodes each path segment', () async {
      await share.dav().getText('Reading/a b#c.json');
      expect(
        share.requests.single.url.toString(),
        '$fakeShareUrl/Reading/a%20b%23c.json',
      );
    });

    test('getText returns null for 404 and decodes UTF-8', () async {
      final dav = share.dav();
      expect(await dav.getText('missing'), isNull);
      share.putText('note.txt', 'zażółć');
      expect(await dav.getText('note.txt'), 'zażółć');
    });

    test('getText throws DavException on an error status', () async {
      share.forceStatus = 500;
      await expectLater(
        share.dav().getText('x'),
        throwsA(
          isA<DavException>()
              .having((e) => e.status, 'status', 500)
              .having((e) => e.path, 'path', 'x'),
        ),
      );
    });

    test(
      'getBytes returns null for 404, bytes otherwise, throws on error',
      () async {
        final dav = share.dav();
        expect(await dav.getBytes('missing'), isNull);
        share.files['a.jpg'] = Uint8List.fromList([7, 8]);
        expect(await dav.getBytes('a.jpg'), [7, 8]);
        share.forceStatus = 500;
        await expectLater(dav.getBytes('a.jpg'), throwsA(isA<DavException>()));
      },
    );

    test('put uploads the bytes and throws on failure', () async {
      final dav = share.dav();
      await dav.put('dir/f.bin', Uint8List.fromList([1, 2, 3]));
      expect(share.files['dir/f.bin'], [1, 2, 3]);
      expect(share.requests.single.method, 'PUT');
      share.forceStatus = 403;
      await expectLater(
        dav.put('dir/f.bin', Uint8List(0)),
        throwsA(isA<DavException>().having((e) => e.status, 'status', 403)),
      );
    });

    test('delete ignores 404, accepts 2xx and throws otherwise', () async {
      final dav = share.dav();
      await dav.delete('missing');
      share.putText('there', 'x');
      await dav.delete('there');
      expect(share.files, isEmpty);
      share.forceStatus = 500;
      await expectLater(dav.delete('there'), throwsA(isA<DavException>()));
    });

    test('an unreachable server becomes status 0', () async {
      final dav = DavClient(
        baseUrl: fakeShareUrl,
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(
        dav.getText('x'),
        throwsA(
          isA<DavException>()
              .having((e) => e.status, 'status', 0)
              .having((e) => e.detail, 'detail', contains('unreachable')),
        ),
      );
    });

    test('defaults to a real client and no credentials', () {
      final dav = DavClient(baseUrl: fakeShareUrl);
      expect((dav.user, dav.password, dav.baseUrl), ('', '', fakeShareUrl));
    });
  });
}
