import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';

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
    expect(find.text('7-51'), findsOneWidget);
    expect(find.text('Czerwony cesarz'), findsOneWidget);
    expect(find.text('44'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
    expect(
      tester.widget<Icon>(iconLabeled('credited')).icon,
      Icons.check_circle,
    );
    // Each photo twice: its thumbnail and its read-out row.
    expect(iconLabeled('start'), findsNWidgets(2));
    expect(iconLabeled('end'), findsNWidgets(2));
    expect(find.text('7'), findsNWidgets(2));
    expect(find.text('?'), findsNWidgets(2));
    expect(find.text('Xi was born in 1953.'), findsOneWidget);
    expect(find.text('Specific and consistent.'), findsOneWidget);
    expect(iconLabeled('Grader'), findsOneWidget);
    await tapVisible(tester, iconLabeled('start').last);
    await tester.pumpAndSettle();
    expect(find.text('KRÓTKI PRZEWODNIK'), findsOneWidget);
    await tapVisible(tester, iconLabeled('end').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, iconLabeled('start').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(api.fetched, contains('processed/a-start.jpg'));
  });

  testWidgets('no summary yet, no grader section', (tester) async {
    api.files['sessions/s1.json'] = _json({'status': 'needs-quiz'});
    await pump(tester);
    expect(tester.widget<Icon>(iconLabeled('No summary yet')).size, 64);
    expect(iconLabeled('Grader'), findsNothing);
  });

  testWidgets('a missing or odd detail file is an hourglass outline', (
    tester,
  ) async {
    final waiting = iconLabeled(
      "The PC has not written this session's details yet",
    );
    await pump(tester);
    expect(waiting, findsOneWidget);
    api.files['sessions/s1.json'] = _json([1, 2]);
    await pump(tester);
    expect(waiting, findsOneWidget);
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
