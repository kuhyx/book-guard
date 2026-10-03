import 'package:book_guard_app/src/guard_state.dart';

/// A full schema-1 snapshot, the way the PC writes it.
Map<String, dynamic> fullState() => {
  'locked': true,
  'reason': 'Read 20 pages to unlock',
  'book': {
    'isbn': '9780735211292',
    'title': 'Atomic Habits',
    'author': 'James Clear',
    'pages': '320',
    'has_file': true,
  },
  'pace': {
    'month': '2026-09',
    'target': 320,
    'pages': 120,
    'required': 250,
    'behind': 130,
    'carried_debt': 20,
  },
  'todo': ['Photograph page 42', 7],
  'sessions': [
    {
      'id': 'session:a-b',
      'start_page': 1,
      'end_page': 20,
      'check_page': 12,
      'pages': 20,
      'minutes': 30,
      'status': 'needs-check-photo',
      'started_at': '2026-09-26T10:00:00Z',
    },
    'garbage',
    {'id': 'session:c-d', 'status': 'needs-quiz', 'start_page': '21'},
    {'status': 'credited'},
  ],
  'open_start': {'page': '55'},
  'generated_at': '2026-09-26T10:30:00Z',
};

/// [fullState] parsed, with [overrides] applied on top.
GuardState sampleState([Map<String, dynamic> overrides = const {}]) =>
    GuardState.fromJson({...fullState(), ...overrides});

/// A plain snapshot for the reading flow: [openStart] if reading, one
/// credited session ending at [lastEnd], one asking for page [check].
GuardState readingState({int? openStart, int? lastEnd, int? check}) =>
    GuardState.fromJson({
      'book': {'isbn': '9788368380002', 'title': 'T', 'pages': 406},
      'pace': const <String, dynamic>{},
      'sessions': [
        if (lastEnd != null)
          {
            'id': 'session:old',
            'start_page': 7,
            'end_page': lastEnd,
            'status': 'credited',
            'started_at': '2026-10-02T19:05:00+02:00',
          },
        if (check != null)
          {
            'id': 'session:chk',
            'start_page': 1,
            'end_page': 40,
            'check_page': check,
            'status': 'needs-check-photo',
            'started_at': '2026-10-03T10:00:00+02:00',
          },
      ],
      'open_start': openStart == null ? null : {'page': openStart},
      'photos': const <Object>[],
    });
