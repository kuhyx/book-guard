import 'dart:convert';

import 'package:book_guard_app/src/open_library.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Biblioteka Narodowa's catalogue: complete for Polish books (legal
/// deposit), where Open Library often has nothing. The phone calls it
/// directly; the desktop web build goes through the wrapper's `/bn` route,
/// because the catalogue sends no CORS header.
///
/// Hits carry no page count: the PC looks the ISBN up again when it is
/// registered and reads the printed count from the full record.
class NationalLibrary {
  /// Creates a client; [web] picks the wrapper route.
  new({http.Client? client, bool? web})
    : _client = client ?? http.Client(),
      _web = web ?? kIsWeb;

  final http.Client _client;
  final bool _web;

  static const _path = '/api/institutions/bibs.json';

  /// Books matching [title] (and [author], when given).
  Future<List<BookHit>> search(String title, {String author = ''}) async {
    final query = {
      'title': title,
      if (author.isNotEmpty) 'author': author,
      'limit': '10',
    };
    final uri = _web
        ? Uri.base.resolve('/bn$_path').replace(queryParameters: query)
        : Uri.https('data.bn.org.pl', _path, query);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Biblioteka Narodowa answered ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final bibs = json is Map<String, dynamic> ? json['bibs'] : null;
    return [
      for (final bib in bibs is List ? bibs : const [])
        if (bib is Map<String, dynamic>) ?_hit(bib),
    ];
  }
}

BookHit? _hit(Map<String, dynamic> bib) {
  final isbn = '${bib['isbnIssn'] ?? ''}'.split(' ').first;
  if (!RegExp(r'^(\d{13}|\d{9}[\dX])$').hasMatch(isbn)) return null;
  final marc = _marc(bib['marc']);
  final title = _strip(marc['245']?['a'] ?? '${bib['title'] ?? ''}');
  final subtitle = _strip(marc['245']?['b'] ?? '');
  return BookHit(
    title: subtitle.isEmpty ? title : '$title: $subtitle',
    author: _firstLast(marc['100']?['a'] ?? ''),
    pages: null,
    isbn: isbn,
  );
}

/// MARC tag -> first value of each subfield code.
Map<String, Map<String, String>> _marc(Object? marc) {
  final fields = <String, Map<String, String>>{};
  final list = marc is Map<String, dynamic> ? marc['fields'] : null;
  for (final field in list is List ? list : const []) {
    if (field is! Map<String, dynamic>) continue;
    for (final MapEntry(:key, :value) in field.entries) {
      if (fields.containsKey(key) || value is! Map<String, dynamic>) continue;
      final subs = <String, String>{};
      for (final sub in value['subfields'] as List? ?? const []) {
        if (sub is! Map<String, dynamic>) continue;
        for (final MapEntry(:key, :value) in sub.entries) {
          subs.putIfAbsent(key, () => '$value');
        }
      }
      fields[key] = subs;
    }
  }
  return fields;
}

String _strip(String text) =>
    text.trim().replaceAll(RegExp(r'[\s:/;,.]+$'), '').trim();

String _firstLast(String name) {
  final parts = _strip(name).split(', ');
  return parts.length > 1 ? '${parts[1]} ${parts[0]}' : parts.first;
}
