import 'package:book_guard_app/src/book_extras.dart';
import 'package:book_guard_app/src/ebook_ref.dart';

export 'package:book_guard_app/src/ebook_ref.dart';

int? _int(Object? raw) => raw is int ? raw : int.tryParse('${raw ?? ''}');

/// A registered book.
class BookInfo {
  /// Creates a book.
  const new({
    required this.isbn,
    required this.title,
    required this.author,
    required this.pages,
    required this.hasFile,
    this.chapters = const [],
    this.chapter,
    this.latestPage,
    this.ebook,
  });

  /// Parses the `book` object.
  factory fromJson(Map<String, dynamic> json) => BookInfo(
    isbn: '${json['isbn'] ?? ''}',
    title: '${json['title'] ?? ''}',
    author: '${json['author'] ?? ''}',
    pages: _int(json['pages']),
    hasFile: json['has_file'] == true,
    chapters: [
      for (final c in json['chapters'] as List? ?? const [])
        if (c is Map<String, dynamic>) ChapterInfo.fromJson(c),
    ],
    chapter: json['chapter'] is Map<String, dynamic>
        ? CurrentChapter.fromJson(json['chapter'] as Map<String, dynamic>)
        : null,
    latestPage: _int(json['latest_page']),
    ebook: EbookRef.fromJson(json['ebook']),
  );

  /// ISBN-10 or -13.
  final String isbn;

  /// Title.
  final String title;

  /// First author, or empty.
  final String author;

  /// Last page that counts, when known.
  final int? pages;

  /// Whether an ebook file is attached (the grader reads it).
  final bool hasFile;

  /// The table of contents, by start page.
  final List<ChapterInfo> chapters;

  /// The chapter of the latest photographed page, when known.
  final CurrentChapter? chapter;

  /// The newest page read, on paper or in the app (an estimate then).
  final int? latestPage;

  /// The in-app reader's files, when the PC has a page map for the book.
  final EbookRef? ebook;
}
