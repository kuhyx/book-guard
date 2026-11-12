/// The zero-text guard over the photo review, the failed photos, the gallery
/// and the photo status chips.
library;

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_api.dart';
import '../support/fake_reader.dart';
import '../support/finders_read.dart';
import '../support/library_api.dart';
import '../support/no_words.dart';
import '../support/no_words_read_support.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  group('the review screen', () {
    Future<void> review(WidgetTester tester, List<(int, Box)> hits) async {
      noAnimations(tester);
      tallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoReview(
            bytes: readBytes,
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
      await api.store.write('photos/a.jpg', readBytes);
      await api.store.write('photos/b.jpg', readBytes);
      await showTab(
        tester,
        FailedPhotos(
          api: api,
          state: withPhotos([
            reading(
              name: 'a.jpg',
              kind: 'other',
              page: null,
              status: 'rejected',
              reason: 'page 19 not found on the photo',
            ),
          ]),
          journal: [
            journalEntry('a.jpg', 'check19', null),
            journalEntry('b.jpg', 'stop', null),
          ],
          reader: FakeReader(fakeScan([])),
          onChanged: () async {},
        ),
      );
      expectNoWords(tester, content: readContent);
      await tester.tap(spoken('This should not fail').first);
      await settle(tester, 10);
      expect(find.byType(ReportDialog), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });

    testWidgets('a reported photo', (tester) async {
      await api.store.write('photos/b.jpg', readBytes);
      await api.reportPhoto(name: 'b.jpg', bytes: readBytes, detail: const {});
      await showTab(
        tester,
        FailedPhotos(
          api: api,
          state: withPhotos(const []),
          journal: [journalEntry('b.jpg', 'stop', null)],
          onChanged: () async {},
        ),
      );
      expect(spoken('Reported'), findsOneWidget);
      expectNoWords(tester, content: readContent);
    });
  });

  testWidgets('the gallery lists every kind and every rejection', (
    tester,
  ) async {
    await showTab(
      tester,
      PhotoGallery(api: api, photos: filedPhotos()),
      scroll: false,
    );
    expectNoWords(tester, content: readContent);
  });

  testWidgets('every photo status chip', (tester) async {
    await showTab(
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
