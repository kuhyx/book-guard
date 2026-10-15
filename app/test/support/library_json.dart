/// A `library.json` document as the PC writes it: one finished book with a
/// session carrying two attempts, and the book being read with a note.
Map<String, dynamic> libraryJson() => {
  'books': [
    {
      'isbn': '9780735211292',
      'title': 'Atomic Habits',
      'author': 'James Clear',
      'status': 'reading',
      'pages': '320',
      'current': true,
      'chapters': [
        {'start': 9, 'title': 'Wstep'},
        {'start': '25', 'title': 'Jeden'},
        'garbage',
      ],
      'first_read_at': '2026-10-02T18:00:00Z',
      'last_read_at': '2026-10-14T19:00:00Z',
      'pages_read': 80,
      'last_page_read': 81,
      'sessions': [
        {
          'id': 'session:a',
          'status': 'credited',
          'start_page': 1,
          'end_page': 20,
          'pages': 20,
          'minutes': 25,
          'ended_at': '2026-10-02T18:30:00Z',
          'attempts': [
            {
              'passed': false,
              'summary': 'first try',
              'feedback': 'mention the habit loop',
              'grader': 'claude:haiku',
            },
            {'passed': true, 'summary': 'second try', 'feedback': 'good'},
          ],
          'photos': [
            {
              'role': 'check',
              'page': 12,
              'file': 'processed/p.jpg',
              'thumb': 'thumbs/p.jpg',
            },
            {'role': 'start', 'file': 'processed/q.jpg', 'thumb': ''},
          ],
        },
        {'id': 'session:b', 'status': 'needs-quiz'},
        7,
      ],
      'notes': [
        {
          'id': 'n1',
          'isbn': '9780735211292',
          'text': 'from the PC',
          'page': 12,
          'chapter': 'Jeden',
          'created_at': '2026-10-03T10:00:00Z',
          'updated_at': '2026-10-03T10:00:00Z',
        },
      ],
    },
    {
      'isbn': '1',
      'title': 'Done Book',
      'status': 'finished',
      'finished_at': '2026-09-20T12:00:00Z',
      'last_page_read': 200,
      'pages': 200,
    },
    {'isbn': '2', 'title': 'Next Book', 'status': 'not-started'},
    'garbage',
  ],
};
