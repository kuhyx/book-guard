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
