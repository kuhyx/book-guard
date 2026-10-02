/// The parts of `state.json` added for the gallery and the table of
/// contents (book-guard `_state_json`).
library;

int? _int(Object? raw) => raw is int ? raw : int.tryParse('${raw ?? ''}');

/// One table-of-contents line.
class ChapterInfo {
  /// Creates a chapter.
  const new({required this.start, required this.title});

  /// Parses `{"start": 25, "title": "..."}`.
  factory fromJson(Map<String, dynamic> json) => ChapterInfo(
    start: _int(json['start']) ?? 0,
    title: '${json['title'] ?? ''}',
  );

  /// The printed page the chapter starts on.
  final int start;

  /// Its title, as printed.
  final String title;

  /// The PC's shape, for the edit request.
  Map<String, Object> toJson() => {'start': start, 'title': title};
}

/// Which chapter the latest photographed page falls in.
class CurrentChapter {
  /// Creates a position.
  const new({required this.number, required this.of, required this.title});

  /// Parses `{"number": 2, "of": 12, "title": "..."}`.
  factory fromJson(Map<String, dynamic> json) => CurrentChapter(
    number: _int(json['number']) ?? 0,
    of: _int(json['of']) ?? 0,
    title: '${json['title'] ?? ''}',
  );

  /// 1-based chapter number.
  final int number;

  /// How many chapters the book has.
  final int of;

  /// The chapter's title.
  final String title;

  /// `Chapter 2 of 12: Title`.
  String get label => 'Chapter $number of $of: $title';
}

/// One uploaded photo, as the PC read it.
class PhotoInfo {
  /// Creates a photo.
  const new({
    required this.name,
    required this.file,
    required this.thumb,
    required this.kind,
    required this.page,
    required this.status,
    required this.reason,
    required this.takenAt,
  });

  /// Parses one `photos` entry.
  factory fromJson(Map<String, dynamic> json) => PhotoInfo(
    name: '${json['name'] ?? ''}',
    file: '${json['file'] ?? ''}',
    thumb: '${json['thumb'] ?? ''}',
    kind: '${json['kind'] ?? ''}',
    page: _int(json['page']),
    status: '${json['status'] ?? ''}',
    reason: '${json['reason'] ?? ''}',
    takenAt: DateTime.tryParse('${json['taken_at']}'),
  );

  /// The name it was uploaded under.
  final String name;

  /// The full photo, relative to `Reading/`.
  final String file;

  /// Its thumbnail, relative to `Reading/`.
  final String thumb;

  /// `page` / `isbn` / `toc` / `other`.
  final String kind;

  /// The printed page number read, pages only.
  final int? page;

  /// `ok` or `rejected`.
  final String status;

  /// Why it was rejected.
  final String reason;

  /// When it was taken.
  final DateTime? takenAt;

  /// Whether the PC took it as what it was meant to be.
  bool get accepted => status == 'ok' && kind != 'other';

  /// One line for the gallery: what the PC made of it.
  String get caption {
    final what = switch (kind) {
      'page' => 'page ${page ?? '?'}',
      'isbn' => 'barcode',
      'toc' => 'contents',
      _ => 'not a page',
    };
    return status == 'rejected' ? '$what - rejected: $reason' : what;
  }
}
