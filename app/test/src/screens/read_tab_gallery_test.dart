import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fake_api.dart';
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
    await tester.scrollUntilVisible(
      find.text('page 7'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Your photos'), findsOneWidget);
  });

  testWidgets('a cancelled pick uploads nothing but still refreshes', (
    tester,
  ) async {
    await pump(tester);
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester);
    expect(api.photos, isEmpty);
    expect(find.textContaining('Uploaded'), findsNothing);
    expect(changed, 1);
  });

  testWidgets('an upload failure is shown, not thrown', (tester) async {
    api.uploadError = shareDown();
    await pump(tester, photo: _photo('x.jpg'));
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
    expect(changed, 1);
  });
}
