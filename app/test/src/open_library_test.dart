import 'dart:convert';

import 'package:book_guard_app/src/open_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

OpenLibrary _library(Object? body, {int status = 200, List<Uri>? seen}) =>
    OpenLibrary(
      client: MockClient((request) async {
        seen?.add(request.url);
        return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
      }),
    );

void main() {
  test('asks for the title with the fields it reads', () async {
    final seen = <Uri>[];
    await _library(const {'docs': <Object>[]}, seen: seen).search('Dune');
    final uri = seen.single;
    expect(uri.host, 'openlibrary.org');
    expect(uri.path, '/search.json');
    expect(uri.queryParameters['title'], 'Dune');
    expect(uri.queryParameters['limit'], '10');
    expect(uri.queryParameters['fields'], contains('number_of_pages_median'));
    expect(uri.queryParameters.containsKey('author'), isFalse);
  });

  test('an author narrows the search', () async {
    final seen = <Uri>[];
    await _library(
      const {'docs': <Object>[]},
      seen: seen,
    ).search('Dune', author: 'Herbert');
    expect(seen.single.queryParameters['author'], 'Herbert');
  });

  test('maps docs to hits, preferring an ISBN-13', () async {
    final hits = await _library({
      'docs': [
        {
          'title': 'Dune',
          'author_name': ['Frank Herbert', 'Other'],
          'number_of_pages_median': 604,
          'isbn': ['0441013597', '9780441013593'],
        },
        {
          'title': 'Short',
          'author_name': <String>[],
          'isbn': ['0441013597'],
        },
        'not a doc',
        <String, dynamic>{},
      ],
    }).search('Dune');
    expect(hits, hasLength(3));
    expect(hits[0].title, 'Dune');
    expect(hits[0].author, 'Frank Herbert');
    expect(hits[0].pages, 604);
    expect(hits[0].isbn, '9780441013593');
    expect(hits[1].author, '');
    expect(hits[1].pages, isNull);
    expect(hits[1].isbn, '0441013597');
    expect(hits[2].title, '');
    expect(hits[2].isbn, isNull);
  });

  test('no docs key means no hits', () async {
    expect(await _library(const <String, dynamic>{}).search('x'), isEmpty);
  });

  test('a failed search throws with the status', () async {
    await expectLater(
      _library(const {}, status: 503).search('x'),
      throwsA(
        isA<Exception>().having(
          (e) => '$e',
          'message',
          contains('Open Library answered 503'),
        ),
      ),
    );
  });

  test('defaults to a real client', () {
    expect(OpenLibrary(), isA<OpenLibrary>());
  });
}
