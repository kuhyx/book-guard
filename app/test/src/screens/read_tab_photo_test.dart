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

  testWidgets('start photo from the camera is uploaded as start_', (
    tester,
  ) async {
    await pump(tester, photo: _photo('IMG_1.jpg'));
    expect(
      find.text('Photograph the open page (number visible) when you start.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester);
    expect(cameras, [true]);
    expect(api.photos, {'start_IMG_1.jpg': _bytes});
    expect(
      find.text('Uploaded - the PC reads it in a few seconds.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(changed, 1);
  });

  testWidgets('desktop, mid-session: stop photo from a file', (tester) async {
    await pump(
      tester,
      state: sampleState(),
      desktop: true,
      photo: _photo('p.jpg'),
    );
    expect(find.textContaining('Reading since p. 55'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
    await tapVisible(tester, find.text('Stop reading'));
    await settle(tester);
    expect(cameras, [false]);
    expect(api.photos.keys, ['stop_p.jpg']);
  });

  testWidgets('a check page gets its own button and file name', (tester) async {
    await pump(tester, state: sampleState(), photo: _photo('c.jpg'));
    await tapVisible(tester, find.text('Photograph page 12'));
    await settle(tester);
    expect(api.photos.keys, ['check12_c.jpg']);
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

  testWidgets('defaults to image_picker, gallery on the desktop', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await pumpTab(
      tester,
      ReadTab(
        api: api,
        state: null,
        desktop: true,
        onChanged: () async => changed++,
      ),
    );
    await tapVisible(tester, find.text('Start reading'));
    await settle(tester);
    expect(calls.single.method, 'pickImage');
    // 1 = ImageSource.gallery; no resize/quality options are sent.
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['source'], 1);
    expect(args['maxWidth'], isNull);
    expect(args['imageQuality'], isNull);
    expect(api.photos, isEmpty);
  });
}
