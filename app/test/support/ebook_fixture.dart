import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:crypto/crypto.dart';

/// The ISBN the in-app reading tests use (Zbrodnia i kara).
const ebookIsbn = '9788382220773';

/// A small ebook: 60 paragraphs of ~420 characters.
final String ebookText = [
  for (var i = 0; i < 60; i++) 'Paragraph $i ${'word$i ' * 60}'.trim(),
].join('\n\n');

/// sha256 hex of [text]'s UTF-8 bytes, as the PC writes `text_sha`.
String shaOf(String text) => sha256.convert(utf8.encode(text)).toString();

/// `ebooks/<isbn>.map.json` for [ebookText]: pages 10-40 spread evenly.
Map<String, dynamic> ebookMapJson({String? text}) {
  final body = text ?? ebookText;
  return {
    'schema': 1,
    'knots': [
      [0, 10.0],
      [body.length, 40.0],
    ],
    'start': 0,
    'end': body.length,
    'last_page': 39,
    'photos': 3,
    'isbn': ebookIsbn,
    'text': 'ebooks/$ebookIsbn.txt',
    'text_sha': shaOf(body),
    'chars': body.length,
    'estimated': true,
  };
}

/// The share's files for the reader: path -> bytes.
Map<String, Uint8List> ebookFiles({String? text}) => {
  'ebooks/$ebookIsbn.map.json': Uint8List.fromList(
    utf8.encode(jsonEncode(ebookMapJson(text: text))),
  ),
  'ebooks/$ebookIsbn.txt': Uint8List.fromList(utf8.encode(text ?? ebookText)),
};

/// A snapshot whose book has the in-app reader.
GuardState ebookState({
  int? latestPage,
  int? openStart,
  List<Map<String, dynamic>> sessions = const [],
  bool reader = true,
}) => GuardState.fromJson({
  'book': {
    'isbn': ebookIsbn,
    'title': 'Zbrodnia i kara',
    'pages': 39,
    'has_file': true,
    'latest_page': latestPage,
    'ebook': reader
        ? {
            'map': 'ebooks/$ebookIsbn.map.json',
            'text': 'ebooks/$ebookIsbn.txt',
            'text_sha': shaOf(ebookText),
            'chars': ebookText.length,
            'photos': 3,
            'generated_at': '2026-10-23T10:00:00+00:00',
          }
        : null,
  },
  'pace': const <String, dynamic>{},
  'sessions': sessions,
  'open_start': openStart == null ? null : {'page': openStart},
  'generated_at': '2026-10-23T10:00:00Z',
});
