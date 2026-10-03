/// The PC's answer to one request file.
class GuardResponse {
  /// Creates a response.
  const new({required this.ok, required this.message, this.passed, this.data});

  /// Whether the request was carried out.
  final bool ok;

  /// A line for the human.
  final String message;

  /// For summaries: whether the session was credited.
  final bool? passed;

  /// For lookups: the fields found.
  final Map<String, dynamic>? data;
}

/// A request answered after the app stopped waiting for it.
typedef LateAnswer = ({String what, GuardResponse response});
