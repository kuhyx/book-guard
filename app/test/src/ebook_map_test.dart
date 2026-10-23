import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/src/ebook_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// The PC's answers for one synthetic map (written by
/// `book_guard/tests/test_core_ebook_map.py`): the app must floor the
/// same pages from the same map.
void main() {
  final goldens = jsonDecode(
    File('test/fixtures/ebook_map_goldens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final map = EbookMap.fromJson(goldens['map'])!;

  List<(int, int)> pairs(String key) => [
    for (final p in goldens[key] as List) ((p as List)[0] as int, p[1] as int),
  ];

  test('pageAt floors exactly as the PC does', () {
    for (final (offset, page) in pairs('page_at')) {
      expect(map.pageAt(offset), page, reason: 'offset $offset');
    }
  });

  test('shownPage never passes the last page', () {
    for (final (offset, page) in pairs('shown_page')) {
      expect(map.shownPage(offset), page, reason: 'offset $offset');
    }
  });

  test('offsetAt matches the PC', () {
    for (final (page, offset) in pairs('offset_at')) {
      expect(map.offsetAt(page), offset, reason: 'page $page');
    }
  });

  test('a map without a known last page shows the raw page', () {
    final open = EbookMap.fromJson({
      'knots': [
        [0, 1.0],
        [100, 3.0],
      ],
    })!;
    expect(open.lastPage, isNull);
    expect(open.shownPage(100), 3);
    expect(open.end, 100);
  });

  test('anything but a rising list of knots is no map', () {
    for (final bad in <Object?>[
      null,
      <String, dynamic>{},
      {
        'knots': [
          [0, 1.0],
        ],
      },
      {
        'knots': [
          [0, 1.0],
          'x',
        ],
      },
      {
        'knots': [
          [0, 1.0],
          [0, 2.0],
        ],
      },
      {
        'knots': [
          [0, 2.0],
          [5, 1.0],
        ],
      },
    ]) {
      expect(EbookMap.fromJson(bad), isNull, reason: '$bad');
    }
  });
}
