/// The PC's answer to one request file.
class GuardResponse {
  /// Creates a response.
  const new({required this.ok, this.code, this.passed, this.data});

  /// Parses a reply file. A reply from an older PC carries only a sentence
  /// (`message`) and no `code`: `code` is null and the app shows a neutral
  /// glyph for it, never the sentence.
  factory fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final data = json['data'];
    return GuardResponse(
      ok: json['ok'] == true,
      code: code is String && code.isNotEmpty ? code : null,
      passed: json['passed'] as bool?,
      data: data is Map<String, dynamic> ? data : null,
    );
  }

  /// Whether the request was carried out.
  final bool ok;

  /// What happened, as a short id (`bad_isbn`, `read`, ...); null for a
  /// reply in the old sentence-only shape. App-side answers use `not_yet`
  /// (the PC has not answered) and `queued` (kept on the phone).
  final String? code;

  /// For summaries: whether the session was credited.
  final bool? passed;

  /// Numbers and fields that go with [code] (a page, the topics to add).
  final Map<String, dynamic>? data;

  /// On a failed summary: the topics to add, the book's own terms.
  List<String> get missing => [
    for (final topic in (data?['missing'] as List<Object?>?) ?? const [])
      if (topic is String && topic.isNotEmpty) topic,
  ];

  /// An integer field of [data], or null.
  int? number(String key) {
    final value = data?[key];
    return value is int ? value : int.tryParse('${value ?? ''}');
  }
}

/// A request answered after the app stopped waiting for it; `what` is the
/// request type (`summary`, `note`, ...).
typedef LateAnswer = ({String what, GuardResponse response});
