import 'package:book_guard_app/src/book_extras.dart';
import 'package:book_guard_app/src/session_info.dart';

export 'package:book_guard_app/src/book_extras.dart';
export 'package:book_guard_app/src/session_info.dart';

/// `Reading/state.json`, as book-guard on the PC writes it (schema 1).
///
/// The PC is the only authority on pace and credit; offline, the app overlays
/// its own photos on the last snapshot (`local_session.dart`).
class GuardState {
  /// Creates a state.
  const new({
    required this.locked,
    required this.reason,
    required this.book,
    required this.pace,
    required this.todo,
    required this.sessions,
    required this.openStart,
    required this.generatedAt,
    this.photos = const [],
    this.claudeDownSince,
  });

  /// Parses the JSON document.
  factory fromJson(Map<String, dynamic> json) {
    final book = json['book'];
    final start = json['open_start'];
    return GuardState(
      locked: json['locked'] == true,
      reason: '${json['reason'] ?? ''}',
      book: book is Map<String, dynamic> ? BookInfo.fromJson(book) : null,
      pace: Pace.fromJson(json['pace'] as Map<String, dynamic>? ?? const {}),
      todo: [for (final t in json['todo'] as List? ?? const []) '$t'],
      sessions: [
        for (final s in json['sessions'] as List? ?? const [])
          if (s is Map<String, dynamic>) SessionInfo.fromJson(s),
      ],
      openStart: start is Map<String, dynamic> ? _int(start['page']) : null,
      generatedAt: DateTime.tryParse('${json['generated_at']}'),
      claudeDownSince: DateTime.tryParse('${json['claude_down_since']}'),
      photos: [
        for (final p in json['photos'] as List? ?? const [])
          if (p is Map<String, dynamic>) PhotoInfo.fromJson(p),
      ],
    );
  }

  /// Whether the PC is locked right now.
  final bool locked;

  /// Why (or why not).
  final String reason;

  /// The book being read, if registered.
  final BookInfo? book;

  /// This month's pace position.
  final Pace pace;

  /// What to do next, most urgent first.
  final List<String> todo;

  /// Recent sessions, oldest first.
  final List<SessionInfo> sessions;

  /// The page of a start photo still waiting for its end photo.
  final int? openStart;

  /// When the PC wrote this snapshot.
  final DateTime? generatedAt;

  /// The newest uploaded photos, newest first.
  final List<PhotoInfo> photos;

  /// Since when the PC's Claude calls (the summary grader) fail, if they do.
  final DateTime? claudeDownSince;

  /// Sessions waiting for their check-page photo.
  List<SessionInfo> get needCheck =>
      sessions.where((s) => s.status == 'needs-check-photo').toList();

  /// Sessions waiting for a summary.
  List<SessionInfo> get needSummary =>
      sessions.where((s) => s.status == 'needs-quiz').toList();
}

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
}

/// The month's pace position.
class Pace {
  /// Creates a pace.
  const new({
    required this.month,
    required this.target,
    required this.pages,
    required this.required,
    required this.behind,
    required this.carriedDebt,
  });

  /// Parses the `pace` object.
  factory fromJson(Map<String, dynamic> json) => Pace(
    month: '${json['month'] ?? ''}',
    target: _int(json['target']) ?? 0,
    pages: _int(json['pages']) ?? 0,
    required: _int(json['required']) ?? 0,
    behind: _int(json['behind']) ?? 0,
    carriedDebt: _int(json['carried_debt']) ?? 0,
  );

  /// `YYYY-MM`.
  final String month;

  /// Pages due this month (1000 + this month's share of the year balance).
  final int target;

  /// Pages credited this month.
  final int pages;

  /// Where the pace line is today.
  final int required;

  /// Pages short of the line.
  final int behind;

  /// This month's share of pages owed from earlier months.
  final int carriedDebt;
}
