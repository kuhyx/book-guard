import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_share.dart';

void main() {
  late FakeShare share;
  late GuardApi api;

  setUp(() {
    share = FakeShare();
    api = GuardApi(
      share.dav(),
      random: Random(1),
      pollEvery: Duration.zero,
      timeout: const Duration(seconds: 5),
    );
  });

  test('defaults need only the share', () {
    expect(GuardApi(share.dav()).dav.baseUrl, fakeShareUrl);
  });

  group('fetchState', () {
    test('is null before the PC wrote one', () async {
      expect(await api.fetchState(), isNull);
      expect(share.requests.single.url.path, '/Reading/state.json');
    });

    test('parses state.json', () async {
      share.putText(
        'Reading/state.json',
        jsonEncode({'locked': true, 'reason': 'behind'}),
      );
      final state = await api.fetchState();
      expect(state?.locked, isTrue);
      expect(state?.reason, 'behind');
    });
  });

  test('newId is 24 lowercase hex characters the PC accepts', () {
    final ids = {for (var i = 0; i < 20; i++) api.newId()};
    expect(ids, hasLength(20));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f]{24}$')));
    }
  });

  group('send', () {
    test('drops a request file and returns the answer', () async {
      share.answer = (request) => {
        'ok': true,
        'message': 'graded ${request['summary']}',
        'passed': true,
      };
      final response = await api.send('summary', {'summary': 'fine'});
      expect(response.ok, isTrue);
      expect(response.message, 'graded fine');
      expect(response.passed, isTrue);

      final put = share.requests.first;
      expect(put.method, 'PUT');
      expect(put.url.path, startsWith('/Reading/requests/'));
      final payload = jsonDecode(put.body) as Map<String, dynamic>;
      expect(payload['type'], 'summary');
      expect(put.url.pathSegments.last, '${payload['id']}.json');
      // The answer is consumed so the share does not fill up.
      expect(share.requests.last.method, 'DELETE');
      expect(
        share.files.keys.where((k) => k.startsWith('Reading/responses/')),
        isEmpty,
      );
    });

    test("carries a lookup's data back", () async {
      share.answer = (_) => {
        'ok': true,
        'message': 'Found',
        'data': {'title': 'Cesarz', 'pages': 406},
      };
      final response = await api.send('lookup', {'isbn': '978'});
      expect(response.data, {'title': 'Cesarz', 'pages': 406});
    });

    test('tolerates a sparse answer', () async {
      share.answer = (_) => {'ok': 'yes'};
      final response = await api.send('set_pages', {'pages': 3});
      expect(response.ok, isFalse);
      expect(response.message, '');
      expect(response.passed, isNull);
    });

    test('keeps polling until the answer appears', () async {
      var polls = 0;
      share.answer = (_) => null;
      final pending = api.send('register', const {});
      // Let a few empty polls go by, then answer as the PC would.
      while (polls < 3) {
        await Future<void>.delayed(Duration.zero);
        polls = share.requests.where((r) => r.method == 'GET').length;
      }
      final id = share.files.keys.single.split('/').last;
      share.putText('Reading/responses/$id', jsonEncode({'ok': true}));
      expect((await pending).ok, isTrue);
    });

    test('a PC that never answers is "not yet"', () async {
      final slow = GuardApi(
        share.dav(),
        pollEvery: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 40),
      );
      final response = await slow.send('summary', const {});
      expect(response.ok, isFalse);
      expect(response.passed, isNull);
      expect(response.message, contains('has not answered yet'));
    });
  });

  group('uploads', () {
    final bytes = Uint8List.fromList([9, 8]);

    test('photos go to the inbox with a safe name', () async {
      expect(
        await api.uploadPhoto(r'C:\cam\IMG 1(2).jpg', bytes),
        'IMG_1_2_.jpg',
      );
      await api.uploadPhoto('/sdcard/DCIM/a/b.jpg', bytes);
      expect(share.files.keys, [
        'Reading/inbox/IMG_1_2_.jpg',
        'Reading/inbox/b.jpg',
      ]);
      expect(share.files['Reading/inbox/b.jpg'], bytes);
    });

    test('books go to books/, and an empty name gets an id', () async {
      await api.uploadBook('Atomic Habits.epub', bytes);
      await api.uploadBook('dir/', bytes);
      final names = share.files.keys.toList();
      expect(names.first, 'Reading/books/Atomic_Habits.epub');
      expect(names.last, matches(RegExp(r'^Reading/books/[0-9a-f]{24}\.bin$')));
    });
  });

  group('reading back', () {
    test('fetchBytes reads under Reading/, null when missing', () async {
      share.files['Reading/thumbs/a.jpg'] = Uint8List.fromList([1, 2]);
      expect(await api.fetchBytes('thumbs/a.jpg'), [1, 2]);
      expect(await api.fetchBytes('thumbs/b.jpg'), isNull);
    });

    test('waitFor polls until the test holds', () async {
      var polls = 0;
      final pending = api.waitFor((s) => s.locked);
      while (polls < 2) {
        await Future<void>.delayed(Duration.zero);
        polls = share.requests.length;
      }
      share.putText('Reading/state.json', jsonEncode({'reason': 'x'}));
      await Future<void>.delayed(Duration.zero);
      share.putText('Reading/state.json', jsonEncode({'locked': true}));
      expect((await pending)?.locked, isTrue);
    });

    test('waitForPhoto finds the reading by upload name', () async {
      share.putText(
        'Reading/state.json',
        jsonEncode({
          'photos': [
            {'name': 'other.jpg', 'kind': 'other'},
            {'name': 'check19_a.jpg', 'kind': 'page', 'page': 19},
          ],
        }),
      );
      final photo = await api.waitForPhoto('check19_a.jpg');
      expect((photo?.kind, photo?.page), ('page', 19));
    });

    test('a PC that never reads the photo gives null', () async {
      final slow = GuardApi(
        share.dav(),
        pollEvery: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 30),
      );
      expect(await slow.waitForPhoto('x.jpg'), isNull);
    });
  });
}
