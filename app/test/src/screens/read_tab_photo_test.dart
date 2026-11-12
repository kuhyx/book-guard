import 'dart:async';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

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

  testWidgets('start photo from the camera is uploaded as start_', (
    tester,
  ) async {
    api.readings['start_IMG_1.jpg'] = reading(page: 7);
    await pump(tester, photo: _photo('IMG_1.jpg'));
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(cameras, [true]);
    expect(api.photos, {'start_IMG_1.jpg': _bytes});
    // One green chip with the page the PC read.
    expect(cueOf(CueKind.ok), findsOneWidget);
    expect(
      find.descendant(of: cueOf(CueKind.ok), matching: find.text('7')),
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
    // Mid-session: stop glyph and the page reading began at.
    expect(
      find.descendant(
        of: buttonSpoken('Stop reading'),
        matching: find.text('55'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
    await tapVisible(tester, spoken('Stop reading'));
    await settle(tester);
    expect(cameras, [false]);
    expect(api.photos.keys, ['stop_p.jpg']);
  });

  testWidgets('a check page gets its own button and file name', (tester) async {
    await pump(tester, state: sampleState(), photo: _photo('c.jpg'));
    expect(find.text('12'), findsOneWidget);
    await tapVisible(tester, find.byIcon(Icons.fact_check));
    await settle(tester);
    expect(api.photos.keys, ['check12_c.jpg']);
  });

  testWidgets('a photo the PC rejects wears its reject glyph', (tester) async {
    api.readings['start_x.jpg'] = reading(kind: 'other', page: null);
    await pump(tester, photo: _photo('x.jpg'));
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(rejected(RejectGlyph.notPage), findsOneWidget);
    expect(cueOf(CueKind.ok), findsNothing);
  });

  testWidgets('a photo the PC has not read yet is a warning cue', (
    tester,
  ) async {
    await pump(tester, photo: _photo('x.jpg'));
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(cueOf(CueKind.warn), findsOneWidget);
  });

  testWidgets('buttons stay locked until the PC has read the photo', (
    tester,
  ) async {
    final read = Completer<PhotoInfo?>();
    final slow = _SlowApi(read.future);
    await pumpTab(
      tester,
      ReadTab(
        api: slow,
        state: null,
        desktop: false,
        onChanged: () async {},
        photoSource: ({required camera}) async => _photo('s.jpg'),
      ),
    );
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    expect(cueWith(Icons.cloud_upload), findsOneWidget);
    final button = tester.widget<FilledButton>(buttonSpoken('Start reading'));
    expect(button.onPressed, isNull);
    read.complete(reading(name: 'start_s.jpg', page: 3));
    await settle(tester);
    expect(cueOf(CueKind.ok), findsOneWidget);
    expect(
      find.descendant(of: cueOf(CueKind.ok), matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('a result arriving after the tab closed is dropped', (
    tester,
  ) async {
    final read = Completer<PhotoInfo?>();
    await pumpTab(
      tester,
      ReadTab(
        api: _SlowApi(read.future),
        state: null,
        desktop: false,
        onChanged: () async {},
        photoSource: ({required camera}) async => _photo('s.jpg'),
      ),
    );
    await tapVisible(tester, spoken('Start reading'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    read.complete(reading(page: 3));
    await settle(tester);
    expect(cueOf(CueKind.ok), findsNothing);
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
    await tapVisible(tester, spoken('Start reading'));
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

/// Holds the PC's reading until the test releases it.
class _SlowApi extends FakeApi {
  new(this._read);

  final Future<PhotoInfo?> _read;

  @override
  Future<PhotoInfo?> waitForPhoto(String name) => _read;
}
