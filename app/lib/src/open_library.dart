import 'dart:convert';

import 'package:http/http.dart' as http;

/// One title-search hit.
class BookHit {
  /// Creates a hit.
  const new({
    required this.title,
    required this.author,
    required this.pages,
    required this.isbn,
  });

  /// Title.
  final String title;

  /// First author, or empty.
  final String author;

  /// Median page count across editions, when known.
  final int? pages;

  /// One ISBN of the work (13-digit preferred).
  final String? isbn;
}

/// Open Library title search, called directly from the app (it sends
/// `Access-Control-Allow-Origin: *`, so the desktop web build can too).
class OpenLibrary {
  /// Creates a client.
  new({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Books matching [title] (and [author], when given), most relevant first.
  Future<List<BookHit>> search(String title, {String author = ''}) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'title': title,
      if (author.isNotEmpty) 'author': author,
      'fields': 'title,author_name,number_of_pages_median,isbn',
      'limit': '10',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Open Library answered ${response.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final doc in json['docs'] as List? ?? const [])
        if (doc is Map<String, dynamic>) _hit(doc),
    ];
  }

  BookHit _hit(Map<String, dynamic> doc) {
    final authors = doc['author_name'];
    final isbns = [for (final i in doc['isbn'] as List? ?? const []) '$i'];
    final thirteen = isbns.where((i) => i.length == 13);
    return BookHit(
      title: '${doc['title'] ?? ''}',
      author: authors is List && authors.isNotEmpty ? '${authors.first}' : '',
      pages: doc['number_of_pages_median'] as int?,
      isbn: thirteen.isNotEmpty
          ? thirteen.first
          : (isbns.isNotEmpty ? isbns.first : null),
    );
  }
}
