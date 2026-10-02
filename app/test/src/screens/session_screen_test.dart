import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

const _session = SessionInfo(
  id: 's1',
  startPage: 7,
  endPage: 51,
  checkPage: 19,
  pages: 44,
  minutes: 43,
  status: 'credited',
  startedAt: null,
  detail: 'sessions/s1.json',
);

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: SessionScreen(api: api, session: _session),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows photos, what was read, the summary and the grader', (
    tester,
  ) async {
    api.files['sessions/s1.json'] = _json({
      'book': 'Czerwony cesarz',
      'photos': [
        {
          'role': 'start',
          'page': 7,
          'file': 'processed/a-start.jpg',
          'thumb': 'thumbs/a.jpg',
          'text': 'KRÓTKI PRZEWODNIK',
        },
        'junk',
        {'role': 'end', 'file': 'processed/b.jpg', 'thumb': 'thumbs/b.jpg'},
      ],
      'summary': 'Xi was born in 1953.',
      'feedback': 'Specific and consistent.',
    });
    await pump(tester);
    expect(find.text('p. 7-51'), findsOneWidget);
    expect(find.text('Czerwony cesarz'), findsOneWidget);
    expect(find.text('44 pages in 43 min - credited'), findsOneWidget);
    expect(find.text('start - p. 7'), findsOneWidget);
    expect(find.text('end - p. ?'), findsOneWidget);
    expect(find.text('Xi was born in 1953.'), findsOneWidget);
    expect(find.text('Specific and consistent.'), findsOneWidget);
    await tapVisible(tester, find.text('start photo, p. 7'));
    await tester.pumpAndSettle();
    expect(find.text('KRÓTKI PRZEWODNIK'), findsOneWidget);
    await tapVisible(tester, find.text('end photo, p. ?'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('start - p. 7'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(api.fetched, contains('processed/a-start.jpg'));
  });

  testWidgets('no summary yet, no grader section', (tester) async {
    api.files['sessions/s1.json'] = _json({'status': 'needs-quiz'});
    await pump(tester);
    expect(find.text('No summary written yet.'), findsOneWidget);
    expect(find.text('Grader'), findsNothing);
  });

  testWidgets('a missing or odd detail file says so', (tester) async {
    await pump(tester);
    expect(
      find.text("The PC has not written this session's details yet."),
      findsOneWidget,
    );
    api.files['sessions/s1.json'] = _json([1, 2]);
    await pump(tester);
    expect(find.textContaining('has not written'), findsOneWidget);
  });

  testWidgets('a spinner while the details download', (tester) async {
    final slow = _Slow();
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(api: slow, session: _session),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    slow.bytes.complete(_json({'summary': 's'}));
    await tester.pumpAndSettle();
    expect(find.text('s'), findsOneWidget);
  });
}

class _Slow extends FakeApi {
  final bytes = Completer<Uint8List?>();

  @override
  Future<Uint8List?> fetchBytes(String path) => bytes.future;
}
