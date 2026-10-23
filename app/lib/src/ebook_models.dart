import 'package:book_guard_app/src/ebook_map.dart';
import 'package:book_guard_app/src/session_info.dart';

/// A downloaded ebook: the served text and its page map.
class Ebook {
  /// Creates an ebook.
  const new(this.map, this.text);

  /// The PC's page map.
  final EbookMap map;

  /// The text, exactly as the PC slices it (offsets are shared).
  final String text;
}

/// "Start reading" in the app: kept on the device at the tap, so closing,
/// killing or restarting the app in between changes nothing.
class ReadingStart {
  /// Creates a start.
  const new({
    required this.id,
    required this.isbn,
    required this.offset,
    required this.startedAt,
    required this.textSha,
  });

  /// Parses the stored form; null if it is not one.
  static ReadingStart? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse('${json['started_at']}');
    final offset = json['offset'];
    if (at == null || offset is! int) return null;
    return ReadingStart(
      id: '${json['id']}',
      isbn: '${json['isbn']}',
      offset: offset,
      startedAt: at,
      textSha: '${json['text_sha']}',
    );
  }

  /// The session's id; its ledger id is `session:ebook-<id>`.
  final String id;

  /// The book.
  final String isbn;

  /// Where reading started in the text.
  final int offset;

  /// When "Start reading" was tapped.
  final DateTime startedAt;

  /// The text it was read in.
  final String textSha;

  /// The stored form.
  Map<String, Object?> toJson() => {
    'id': id,
    'isbn': isbn,
    'offset': offset,
    'started_at': startedAt.toUtc().toIso8601String(),
    'text_sha': textSha,
  };
}

/// A session read in the app and stopped, kept until the PC lists it, so
/// its summary can be written at once -- even with the PC off.
class AppSession {
  /// Creates a session.
  const new({
    required this.key,
    required this.requestId,
    required this.startPage,
    required this.endPage,
    required this.startedAt,
    required this.endedAt,
  });

  /// Parses the stored form.
  factory fromJson(Map<String, dynamic> json) => AppSession(
    key: '${json['key']}',
    requestId: '${json['request_id']}',
    startPage: json['start_page'] as int,
    endPage: json['end_page'] as int,
    startedAt: DateTime.parse('${json['started_at']}'),
    endedAt: DateTime.parse('${json['ended_at']}'),
  );

  /// The app's id for it.
  final String key;

  /// The `ebook_session` request that carries it to the PC.
  final String requestId;

  /// Where reading started (estimated paper page).
  final int startPage;

  /// The first page not read (estimated).
  final int endPage;

  /// The Start tap.
  final DateTime startedAt;

  /// The Stop tap.
  final DateTime endedAt;

  /// The PC's id for it.
  String get sessionId => 'session:ebook-$key';

  /// It as the summary panel takes it, the way the PC will list it.
  SessionInfo get info => SessionInfo(
    id: sessionId,
    startPage: startPage,
    endPage: endPage,
    checkPage: null,
    pages: endPage - startPage,
    minutes: endedAt.difference(startedAt).inMinutes,
    status: 'needs-quiz',
    startedAt: startedAt,
    endedAt: endedAt,
    estimated: true,
  );

  /// The stored form.
  Map<String, Object?> toJson() => {
    'key': key,
    'request_id': requestId,
    'start_page': startPage,
    'end_page': endPage,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
  };
}
