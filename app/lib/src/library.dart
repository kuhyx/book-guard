/// `Reading/library.json`, as book-guard's `_library.py` writes it (schema
/// 1): every book ever registered, its sessions with every graded summary
/// in full, and the reader's notes.
library;

int? _int(Object? raw) => raw is int ? raw : int.tryParse('${raw ?? ''}');

List<Map<String, dynamic>> _maps(Object? raw) => [
  for (final item in raw as List? ?? const [])
    if (item is Map<String, dynamic>) item,
];

/// Every book, the one being read first.
class Library {
  /// Creates a library.
  const new(this.books);

  /// Parses the document.
  factory fromJson(Map<String, dynamic> json) =>
      Library([for (final b in _maps(json['books'])) LibraryBook.fromJson(b)]);

  /// The books.
  final List<LibraryBook> books;
}

/// One book, all time.
class LibraryBook {
  /// Creates a book.
  const new({
    required this.isbn,
    required this.title,
    required this.author,
    required this.status,
    this.pages,
    this.current = false,
    this.chapters = const [],
    this.finishedAt,
    this.firstReadAt,
    this.lastReadAt,
    this.pagesRead = 0,
    this.lastPageRead,
    this.sessions = const [],
    this.notes = const [],
  });

  /// Parses one `books[]` entry.
  factory fromJson(Map<String, dynamic> json) => LibraryBook(
    isbn: '${json['isbn'] ?? ''}',
    title: '${json['title'] ?? ''}',
    author: '${json['author'] ?? ''}',
    status: '${json['status'] ?? ''}',
    pages: _int(json['pages']),
    current: json['current'] == true,
    chapters: [
      for (final c in _maps(json['chapters']))
        (start: _int(c['start']) ?? 0, title: '${c['title'] ?? ''}'),
    ],
    finishedAt: DateTime.tryParse('${json['finished_at']}'),
    firstReadAt: DateTime.tryParse('${json['first_read_at']}'),
    lastReadAt: DateTime.tryParse('${json['last_read_at']}'),
    pagesRead: _int(json['pages_read']) ?? 0,
    lastPageRead: _int(json['last_page_read']),
    sessions: [
      for (final s in _maps(json['sessions'])) LibrarySession.fromJson(s),
    ],
    notes: [for (final n in _maps(json['notes'])) Note.fromJson(n)],
  );

  /// ISBN.
  final String isbn;

  /// Title.
  final String title;

  /// First author, or empty.
  final String author;

  /// `finished` (all time), `reading` or `not-started`.
  final String status;

  /// The last page that counts, when known.
  final int? pages;

  /// Whether this is the book being read now.
  final bool current;

  /// The table of contents.
  final List<({int start, String title})> chapters;

  /// When a credited session reached the last page.
  final DateTime? finishedAt;

  /// When the first session began.
  final DateTime? firstReadAt;

  /// When the newest session ended.
  final DateTime? lastReadAt;

  /// Pages credited, all sessions.
  final int pagesRead;

  /// The furthest credited end page.
  final int? lastPageRead;

  /// Every session, oldest first.
  final List<LibrarySession> sessions;

  /// The PC's copy of the notes.
  final List<Note> notes;
}

/// One session with every graded attempt.
class LibrarySession {
  /// Creates a session.
  const new({
    required this.id,
    required this.status,
    this.startPage,
    this.endPage,
    this.pages,
    this.minutes,
    this.endedAt,
    this.attempts = const [],
    this.photos = const [],
    this.estimated = false,
  });

  /// Parses one `sessions[]` entry.
  factory fromJson(Map<String, dynamic> json) => LibrarySession(
    estimated: json['estimated'] == true,
    id: '${json['id'] ?? ''}',
    status: '${json['status'] ?? ''}',
    startPage: _int(json['start_page']),
    endPage: _int(json['end_page']),
    pages: _int(json['pages']),
    minutes: _int(json['minutes']),
    endedAt: DateTime.tryParse('${json['ended_at']}'),
    attempts: [
      for (final a in _maps(json['attempts']))
        (
          passed: a['passed'] == true,
          summary: '${a['summary'] ?? ''}',
          feedback: '${a['feedback'] ?? ''}',
          grader: '${a['grader'] ?? ''}',
        ),
    ],
    photos: [
      for (final p in _maps(json['photos']))
        (
          role: '${p['role'] ?? ''}',
          page: _int(p['page']),
          file: '${p['file'] ?? ''}',
          thumb: '${p['thumb'] ?? ''}',
        ),
    ],
  );

  /// Ledger id.
  final String id;

  /// `credited`, `needs-quiz`, ...
  final String status;

  /// Read in the app: the pages are the PC's estimate.
  final bool estimated;

  /// First page.
  final int? startPage;

  /// Where reading stopped.
  final int? endPage;

  /// Pages read.
  final int? pages;

  /// Minutes read.
  final int? minutes;

  /// When reading stopped.
  final DateTime? endedAt;

  /// Each summary sent and the grader's reply, oldest first (full text).
  final List<({bool passed, String summary, String feedback, String grader})>
  attempts;

  /// The session's photos on the PC (thumbs outlive the phone's 40).
  final List<({String role, int? page, String file, String thumb})> photos;
}

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
