part of 'library.dart';

/// A note on a book, optionally at a page or chapter.
class Note {
  /// Creates a note.
  const new({
    required this.id,
    required this.isbn,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.page,
    this.chapter = '',
  });

  /// Parses a note (the PC's or the phone's copy).
  factory fromJson(Map<String, dynamic> json) => Note(
    id: '${json['id'] ?? ''}',
    isbn: '${json['isbn'] ?? ''}',
    text: '${json['text'] ?? ''}',
    page: _int(json['page']),
    chapter: '${json['chapter'] ?? ''}',
    createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime(2000),
    updatedAt: DateTime.tryParse('${json['updated_at']}') ?? DateTime(2000),
  );

  /// The phone-made id; an edit keeps it.
  final String id;

  /// The book.
  final String isbn;

  /// What was written.
  final String text;

  /// The page it is about, if any.
  final int? page;

  /// The chapter it is about, or empty.
  final String chapter;

  /// When first written.
  final DateTime createdAt;

  /// When last edited (the newer edit wins on the PC).
  final DateTime updatedAt;

  /// The phone's copy, and the body of a `note` request.
  Map<String, Object?> toJson() => {
    'id': id,
    'isbn': isbn,
    'text': text,
    'page': page,
    'chapter': chapter,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
