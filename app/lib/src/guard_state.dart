/// `Reading/state.json`, as book-guard on the PC writes it (schema 1).
///
/// The app never derives pace or session state itself: the PC is the only
/// authority, and everything shown comes from here.
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
  });

  /// Parses the `book` object.
  factory fromJson(Map<String, dynamic> json) => BookInfo(
    isbn: '${json['isbn'] ?? ''}',
    title: '${json['title'] ?? ''}',
    author: '${json['author'] ?? ''}',
    pages: _int(json['pages']),
    hasFile: json['has_file'] == true,
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

  /// Pages due this month (300 + carried debt).
  final int target;

  /// Pages credited this month.
  final int pages;

  /// Where the pace line is today.
  final int required;

  /// Pages short of the line.
  final int behind;

  /// Debt carried in from last month.
  final int carriedDebt;
}

/// One reading session.
class SessionInfo {
  /// Creates a session.
  const new({
    required this.id,
    required this.startPage,
    required this.endPage,
    required this.checkPage,
    required this.pages,
    required this.minutes,
    required this.status,
    required this.startedAt,
  });

  /// Parses one `sessions[]` entry.
  factory fromJson(Map<String, dynamic> json) => SessionInfo(
    id: '${json['id'] ?? ''}',
    startPage: _int(json['start_page']) ?? 0,
    endPage: _int(json['end_page']) ?? 0,
    checkPage: _int(json['check_page']),
    pages: _int(json['pages']) ?? 0,
    minutes: _int(json['minutes']) ?? 0,
    status: '${json['status'] ?? ''}',
    startedAt: DateTime.tryParse('${json['started_at']}'),
  );

  /// Ledger id (`session:<hash>-<hash>`).
  final String id;

  /// First page.
  final int startPage;

  /// Page where reading stopped.
  final int endPage;

  /// The page to photograph as proof, if one is needed.
  final int? checkPage;

  /// Pages read.
  final int pages;

  /// Minutes read.
  final int minutes;

  /// `needs-check-photo`, `needs-quiz`, `credited`, `failed-quiz`, `too-fast`.
  final String status;

  /// When the start photo was taken.
  final DateTime? startedAt;
}
