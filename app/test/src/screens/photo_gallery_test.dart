import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_read.dart';

/// A valid 1x1 PNG, so Image.memory has something to decode.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, //
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  test('the status is data: what the PC saw, never a sentence', () {
    final unread = PhotoStatus.of(null);
    expect(unread.cue.kind, CueKind.warn);
    expect(unread.good, isNull);
    final seven = PhotoStatus.of(reading(page: 7));
    expect((seven.cue.kind, seven.page, seven.good), (CueKind.ok, 7, true));
    expect(
      PhotoStatus.of(reading(kind: 'toc')).cue.glyph,
      Icons.format_list_numbered,
    );
    expect(PhotoStatus.of(reading(kind: 'isbn')).cue.glyph, Icons.qr_code_2);
    final late = PhotoStatus.of(
      reading(status: 'rejected', reason: 'too late'),
    );
    expect((late.reject, late.good), ('too late', false));
    // Status ok but the PC took it for something else: rejected, no reason.
    final other = PhotoStatus.of(reading(kind: 'other', page: null));
    expect((other.reject, other.good), ('', false));
  });

  test('a photo kind and a label each have an icon', () {
    expect(photoKindGlyph(PhotoKind.barcode).$1, Icons.qr_code_2);
    expect(labelGlyph('start'), (Icons.play_arrow, 'start', null));
    expect(labelGlyph('stop'), (Icons.stop, 'stop', null));
    expect(labelGlyph('check115'), (Icons.fact_check, 'check page', 115));
    expect(labelGlyph('odd').$1, Icons.photo_camera);
  });

  testWidgets('lists photos as icons, numbers, times and thumbnails', (
    tester,
  ) async {
    api.files['thumbs/abc.jpg'] = _png;
    final undated = reading(kind: 'other', page: null);
    await pumpTab(
      tester,
      PhotoGallery(
        api: api,
        photos: [
          reading(),
          PhotoInfo(
            name: undated.name,
            file: undated.file,
            thumb: 'thumbs/missing.jpg',
            kind: undated.kind,
            page: null,
            status: 'ok',
            reason: '',
            takenAt: null,
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.text('19'), findsOneWidget);
    expect(find.byIcon(Icons.description), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(RejectBadge), findsOneWidget);
    expect(rejected(RejectGlyph.notPage), findsWidgets);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    // Each thumbnail is fetched once, however often the list rebuilds.
    await tester.pump();
    expect(api.fetched, ['thumbs/abc.jpg', 'thumbs/missing.jpg']);
    // The time sits behind a long-press, with the mark and the verdict.
    final sheet = find.byType(BottomSheet);
    await tester.longPress(find.text('19'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text('02.10 20:14')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // The undated one.
    await tester.longPress(find.byType(Card).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: spoken('time unknown')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(RejectBadge)),
      findsOneWidget,
    );
  });

  testWidgets('the long-press sheet opens the photo full size', (tester) async {
    api.files['processed/abc-x.jpg'] = _png;
    await pumpTab(tester, PhotoGallery(api: api, photos: [reading()]));
    await tester.longPress(find.text('19'));
    await tester.pumpAndSettle();
    await tester.tap(spoken('full size'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('a thumbnail still downloading shows a spinner', (tester) async {
    final slow = _SlowBytes();
    await pumpTab(tester, PhotoGallery(api: slow, photos: [reading()]));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    slow.bytes.complete(_png);
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping a photo opens it full size, zoomable', (tester) async {
    api.files['processed/abc-x.jpg'] = _png;
    await pumpTab(tester, PhotoGallery(api: api, photos: [reading()]));
    await tester.tap(find.text('19'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(api.fetched.last, 'processed/abc-x.jpg');
  });
}

class _SlowBytes extends FakeApi {
  final bytes = Completer<Uint8List?>();

  @override
  Future<Uint8List?> fetchBytes(String path) => bytes.future;
}
