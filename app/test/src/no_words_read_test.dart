import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../support/fake_api.dart';
import '../support/fake_reader.dart';
import '../support/finders_read.dart';
import '../support/library_api.dart';
import '../support/no_words.dart';
import '../support/states.dart';

/// Text the PC or the reader wrote: shown as it is.
const _content = ['the habit loop', 'Kaladin', 'Atomic Habits', 'James Clear'];

/// What the PC appends to a number reason.
const _boxIt = ' -- box the page number in the app, or retake the photo';

final Uint8List _bytes = previewPng;

JournalEntry _entry(String name, String label, int? page) => JournalEntry(
  name: name,
  label: label,
  sha: 'f' * 64,
  takenAt: DateTime.utc(2026, 10, 3, 12, 27),
  page: page,
);

/// Every kind of photo the PC can have filed, with every rejection reason.
List<PhotoInfo> _photos() => [
  for (final reason in [
    'page number unclear (12 or 21)$_boxIt',
    'no page number found$_boxIt',
    'no page on the photo',
    'the PC could not read the photo',
    'no EXIF capture time',
    'overlaps another session',
  ])
    reading(
      name: 'r${reason.length}.jpg',
      kind: 'other',
      page: null,
      status: 'rejected',
      reason: reason,
    ),
  reading(),
  reading(kind: 'toc', page: null),
  reading(kind: 'isbn', page: null),
];

GuardState _withPhotos(List<PhotoInfo> photos, [GuardState? base]) {
  final s = base ?? sampleState();
  return GuardState(
    locked: s.locked,
    reason: s.reason,
    book: s.book,
    pace: s.pace,
    todo: s.todo,
    sessions: s.sessions,
    openStart: s.openStart,
    generatedAt: s.generatedAt,
    photos: photos,
  );
}

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool scroll = true,
  }) async {
    tallSurface(tester);
    await pumpTab(tester, scroll ? SingleChildScrollView(child: child) : child);
    await settle(tester, 10);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Widget tab({
    GuardState? state,
    List<JournalEntry> journal = const [],
    List<Capture> captures = const [],
    bool desktop = false,
  }) => ReadTab(
    api: api,
    state: state,
    desktop: desktop,
    onChanged: () async {},
    reader: desktop ? null : FakeReader(fakeScan([])),
    local: localView(state, journal),
    journal: journal,
    captures: captures,
    photoSource: ({required camera}) async =>
        XFile.fromData(_bytes, path: '/DCIM/IMG.jpg'),
  );

  group('the Read tab', () {
    testWidgets('empty: no state at all', (tester) async {
      await show(tester, tab(), scroll: false);
      expectNoWords(tester, content: _content);
    });

    testWidgets('mid-session with a summary, a check page and photos', (
      tester,
    ) async {
      await show(tester, tab(state: _withPhotos(_photos())), scroll: false);
      expectNoWords(tester, content: _content);
    });

    testWidgets('desktop, waiting photos and a stored capture', (tester) async {
      final journal = [_entry('start_a.jpg', 'start', 51)];
      await show(
        tester,
        tab(
          state: readingState(openStart: 51),
          desktop: true,
          journal: journal,
          captures: [
            Capture(
              id: 'a1',
              label: 'check19',
              fileName: 'IMG.jpg',
              takenAt: DateTime(2026, 10, 23, 10, 6),
            ),
          ],
        ),
        scroll: false,
      );
      expectNoWords(tester, content: _content);
    });

    testWidgets('with failed photos listed', (tester) async {
      await api.store.write('photos/stop_b.jpg', _bytes);
      await show(
        tester,
        tab(
          state: _withPhotos([
            reading(
              name: 'start_a.jpg',
              kind: 'other',
              page: null,
              status: 'rejected',
              reason: 'no page number found',
            ),
          ]),
          journal: [
            _entry('start_a.jpg', 'start', 51),
            _entry('stop_b.jpg', 'stop', null),
          ],
        ),
        scroll: false,
      );
      // They live on the photos page; the switch carries a dot meanwhile.
      expect(find.byType(Badge), findsOneWidget);
      await tester.tap(spoken('photos'));
      await settle(tester, 10);
      expect(spoken('failed photos'), findsOneWidget);
      expectNoWords(tester, content: _content);
    });

    testWidgets('an upload error is an icon snackbar', (tester) async {
      api.uploadError = shareDown();
      await show(
        tester,
        tab(state: sampleState(), desktop: true),
        scroll: false,
      );
      await tester.tap(spoken('Stop reading'));
      await settle(tester, 10);
      expect(inSnack(cueOf(CueKind.error)), findsOneWidget);
      expectNoWords(tester, content: _content);
    });
  });

  group('the summary', () {
    SessionInfo session({Map<String, Object?>? retry}) => SessionInfo.fromJson({
      'id': 'session:a-b',
      'start_page': 51,
      'end_page': 104,
      'pages': 53,
      'status': 'needs-quiz',
      'retry': retry,
    });

    Widget panel(SessionInfo s, {GuardState? state, Pace? pace}) =>
        SummaryPanel(
          api: api,
          session: s,
          onChanged: () async {},
          state: state,
          pace: pace,
        );

    testWidgets('empty, then long enough', (tester) async {
      await show(tester, panel(session()));
      expectNoWords(tester, content: _content);
      await tester.enterText(find.byType(TextField), 'x' * 160);
      await tester.pump();
      expect(spoken('long enough'), findsOneWidget);
      expectNoWords(tester, content: _content);
    });

    testWidgets('a failure to rewrite lists the topics', (tester) async {
      await show(
        tester,
        panel(
          session(
            retry: {
              'feedback': 'Name two events.',
              'summary': 'Kaladin trains.',
              'missing': ['the habit loop', 'Kaladin'],
            },
          ),
        ),
      );
      expect(find.text('Name two events.'), findsNothing);
      expectNoWords(tester, content: _content);
    });

    testWidgets('with the grader, an outage and the bonus bolt', (
      tester,
    ) async {
      await api.markGrading('session:a-b');
      final state = GuardState.fromJson({
        'claude_down_since': DateTime.now().toIso8601String(),
        'claude_down_until': DateTime.now()
            .add(const Duration(hours: 3))
            .toIso8601String(),
      });
      await show(
        tester,
        panel(
          session(),
          state: state,
          pace: Pace.fromJson(const {
            'today_required': 30,
            'pages_today': 0,
            'bonus_today': false,
          }),
        ),
      );
      expect(find.byType(GraderNoteChip), findsOneWidget);
      expect(spoken('gaming bonus'), findsOneWidget);
      expectNoWords(tester, content: _content);
    });

    for (final answer in [
      const GuardResponse(ok: true, code: 'passed', passed: true),
      const GuardResponse(ok: true, code: 'ungraded', passed: true),
      const GuardResponse(
        ok: true,
        code: 'failed',
        passed: false,
        data: {
          'missing': ['the habit loop'],
        },
      ),
      const GuardResponse(ok: false, code: 'not_yet'),
      const GuardResponse(ok: true, code: 'queued'),
      // An old PC's sentence-only reply: neutral glyph, never the sentence.
      GuardResponse.fromJson(const {'ok': true, 'message': 'Credited 18.'}),
    ]) {
      testWidgets('the verdict ${answer.code}', (tester) async {
        api.onSend = (_) async => answer;
        await show(tester, panel(session()));
        await tester.enterText(find.byType(TextField), 'x' * 160);
        await tester.tap(spoken('Submit summary'));
        await settle(tester, 10);
        expectNoWords(tester, content: _content);
      });
    }

    testWidgets('a send that failed', (tester) async {
      api.onSend = (_) async => throw shareDown();
      await show(tester, panel(session()));
      await tester.tap(spoken('Submit summary'));
      await settle(tester, 10);
      expectNoWords(tester, content: _content);
    });
  });

  group('the review screen', () {
    Future<void> review(WidgetTester tester, List<(int, Box)> hits) async {
      noAnimations(tester);
      tallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoReview(
            bytes: _bytes,
            scan: fakeScan(hits),
            reader: FakeReader(fakeScan(hits)),
            context: const PageContext(),
          ),
        ),
      );
      await settle(tester, 10);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
    }

    testWidgets('a number read: tick and the number', (tester) async {
      await review(tester, [(51, (left: 17, top: 54, right: 23, bottom: 58))]);
      expect(chosenPage(51), findsOneWidget);
      expectNoWords(tester);
    });

    testWidgets('no number: the pulsing viewfinder', (tester) async {
      await review(tester, []);
      expect(pulse(), findsOneWidget);
      expectNoWords(tester);
    });

    testWidgets('two candidates: unclear, pulsing', (tester) async {
      await review(tester, [
        (3, (left: 18, top: 4, right: 22, bottom: 8)),
        (51, (left: 17, top: 54, right: 23, bottom: 58)),
      ]);
      expect(pulse(), findsOneWidget);
      expectNoWords(tester);
    });
  });

  group('failed photos', () {
    testWidgets('cards, then the report dialog open', (tester) async {
      await api.store.write('photos/a.jpg', _bytes);
      await api.store.write('photos/b.jpg', _bytes);
      await show(
        tester,
        FailedPhotos(
          api: api,
          state: _withPhotos([
            reading(
              name: 'a.jpg',
              kind: 'other',
              page: null,
              status: 'rejected',
              reason: 'page 19 not found on the photo',
            ),
          ]),
          journal: [
            _entry('a.jpg', 'check19', null),
            _entry('b.jpg', 'stop', null),
          ],
          reader: FakeReader(fakeScan([])),
          onChanged: () async {},
        ),
      );
      expectNoWords(tester, content: _content);
      await tester.tap(spoken('This should not fail').first);
      await settle(tester, 10);
      expect(find.byType(ReportDialog), findsOneWidget);
      expectNoWords(tester, content: _content);
    });

    testWidgets('a reported photo', (tester) async {
      await api.store.write('photos/b.jpg', _bytes);
      await api.reportPhoto(name: 'b.jpg', bytes: _bytes, detail: const {});
      await show(
        tester,
        FailedPhotos(
          api: api,
          state: _withPhotos(const []),
          journal: [_entry('b.jpg', 'stop', null)],
          onChanged: () async {},
        ),
      );
      expect(spoken('Reported'), findsOneWidget);
      expectNoWords(tester, content: _content);
    });
  });

  testWidgets('the gallery lists every kind and every rejection', (
    tester,
  ) async {
    await show(
      tester,
      PhotoGallery(api: api, photos: _photos()),
      scroll: false,
    );
    expectNoWords(tester, content: _content);
  });

  testWidgets('every photo status chip', (tester) async {
    await show(
      tester,
      Column(
        children: [
          for (final status in [
            PhotoStatus.kept,
            PhotoStatus.discarded,
            PhotoStatus.reading,
            PhotoStatus.saved(7),
            PhotoStatus.uploaded(null),
            PhotoStatus.of(null),
            PhotoStatus.of(reading()),
            PhotoStatus.of(reading(kind: 'toc')),
            PhotoStatus.of(reading(kind: 'isbn')),
            PhotoStatus.of(reading(kind: 'other', status: 'rejected')),
          ])
            PhotoStatusChip(status),
        ],
      ),
    );
    expectNoWords(tester);
  });
}
