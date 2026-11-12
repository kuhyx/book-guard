import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/photo_reports.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';
import '../../support/states.dart';

final _bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);

/// A picked photo; on dart:io the name comes from the path.
XFile _photo(String name) => XFile.fromData(_bytes, path: '/DCIM/$name');

void main() {
  late FakeApi api;
  late int changed;
  late List<bool> cameras;

  setUp(() {
    api = FakeApi();
    changed = 0;
    cameras = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    GuardState? state,
    bool desktop = false,
    XFile? photo,
  }) => pumpTab(
    tester,
    ReadTab(
      api: api,
      state: state,
      desktop: desktop,
      onChanged: () async => changed++,
      photoSource: ({required camera}) async {
        cameras.add(camera);
        return photo;
      },
    ),
  );

  testWidgets('the photos the PC has read are listed', (tester) async {
    await pump(
      tester,
      state: sampleState({
        'photos': [
          {'name': 'a.jpg', 'kind': 'page', 'page': 7, 'status': 'ok'},
        ],
      }),
    );
    await tester.tap(spoken('photos'));
    await settle(tester);
    expect(
      find.descendant(of: find.byType(PhotoMark), matching: find.text('7')),
      findsOneWidget,
    );
    // And back to the session page.
    await tester.tap(spoken('session'));
    await settle(tester);
    expect(spoken('Stop reading'), findsOneWidget);
  });

  testWidgets('a cancelled pick uploads nothing but still refreshes', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(api.photos, isEmpty);
    expect(cueWith(Icons.cloud_upload), findsNothing);
    expect(changed, 1);
  });

  testWidgets('an upload failure is shown, not thrown', (tester) async {
    api.uploadError = shareDown();
    await pump(tester, photo: _photo('x.jpg'));
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(cueOf(CueKind.error), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('a failed photo dots the photos switch until dismissed', (
    tester,
  ) async {
    final journal = [
      JournalEntry(
        name: 'lost.jpg',
        label: 'start',
        sha: 'a' * 64,
        takenAt: DateTime.utc(2026, 10, 3, 12),
      ),
    ];
    Future<void> show() async {
      await pumpTab(
        tester,
        ReadTab(
          api: api,
          state: sampleState(),
          desktop: false,
          onChanged: () async {},
          journal: journal,
        ),
      );
      await settle(tester);
    }

    await show();
    expect(find.byType(Badge), findsOneWidget);
    await api.dismissPhoto('lost.jpg');
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(find.byType(Badge), findsNothing);
  });
}
