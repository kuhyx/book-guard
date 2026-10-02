import 'dart:convert';

import 'package:book_guard_app/src/national_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> _bib(String isbn, {bool marc = true}) => {
  'isbnIssn': '$isbn 83',
  'title': 'Raw title / with junk',
  if (marc)
    'marc': {
      'fields': [
        {'001': 'b1'},
        'junk',
        {
          '100': {
            'subfields': [
              {'a': 'Sheridan, Michael'},
              'junk',
            ],
          },
        },
        {
          '245': {
            'subfields': [
              {'a': 'Czerwony cesarz :'},
              {'b': 'Xi Jinping i Chiny /'},
            ],
          },
        },
        {
          '245': {
            'subfields': [
              {'a': 'ignored second 245'},
            ],
          },
        },
      ],
    },
};

NationalLibrary _library(
  Object body, {
  int status = 200,
  List<Uri>? seen,
  bool web = false,
}) => NationalLibrary(
  web: web,
  client: MockClient((request) async {
    seen?.add(request.url);
    return http.Response(jsonEncode(body), status);
  }),
);

void main() {
  test('the phone asks the catalogue directly, with the author', () async {
    final seen = <Uri>[];
    await _library(const {
      'bibs': <Object>[],
    }, seen: seen).search('Cesarz', author: 'Sheridan');
    final uri = seen.single;
    expect(uri.host, 'data.bn.org.pl');
    expect(uri.path, '/api/institutions/bibs.json');
    expect(uri.queryParameters, {
      'title': 'Cesarz',
      'author': 'Sheridan',
      'limit': '10',
    });
  });

  test('the web build goes through the wrapper, author optional', () async {
    final seen = <Uri>[];
    await _library(
      const {'bibs': <Object>[]},
      seen: seen,
      web: true,
    ).search('Cesarz');
    final uri = seen.single;
    expect(uri.path, '/bn/api/institutions/bibs.json');
    expect(uri.queryParameters.containsKey('author'), isFalse);
  });

  test('maps MARC records to hits; non-ISBN records are dropped', () async {
    final hits = await _library({
      'bibs': [
        _bib('9788368380002'),
        _bib('1642-5685'),
        _bib('836838000X', marc: false),
        'junk',
      ],
    }).search('Cesarz');
    expect(hits, hasLength(2));
    final first = hits.first;
    expect(
      (first.title, first.author, first.pages, first.isbn),
      (
        'Czerwony cesarz: Xi Jinping i Chiny',
        'Michael Sheridan',
        null,
        '9788368380002',
      ),
    );
    final bare = hits.last;
    expect((bare.title, bare.author), ('Raw title / with junk', ''));
  });

  test('odd documents give no hits', () async {
    expect(await _library(const <Object>[]).search('x'), isEmpty);
    expect(await _library(const {'bibs': 'no'}).search('x'), isEmpty);
  });

  test('a failed search throws with the status', () {
    expect(
      _library(const {}, status: 503).search('x'),
      throwsA(
        predicate((e) => '$e'.contains('Biblioteka Narodowa answered 503')),
      ),
    );
  });

  test('defaults to a real client off the web', () {
    expect(NationalLibrary(), isA<NationalLibrary>());
  });
}
