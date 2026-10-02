import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

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

  test('the verdict says what the PC saw', () {
    expect(photoVerdict(null), contains('has not read it yet'));
    expect(photoVerdict(reading(page: 7)), 'Read as page 7.');
    expect(photoVerdict(reading(kind: 'toc')), 'Contents read.');
    expect(photoVerdict(reading(kind: 'isbn')), 'Barcode read.');
    expect(
      photoVerdict(reading(status: 'rejected', reason: 'too late')),
      'Not accepted: page 19 - rejected: too late. Retake it with the page '
      'number in view.',
    );
  });

  testWidgets('lists photos with captions, times and thumbnails', (
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
    expect(find.text('page 19'), findsOneWidget);
    expect(find.text('not a page'), findsOneWidget);
    expect(find.text('time unknown'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    // Each thumbnail is fetched once, however often the list rebuilds.
    await tester.pump();
    expect(api.fetched, ['thumbs/abc.jpg', 'thumbs/missing.jpg']);
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
    await tester.tap(find.text('page 19'));
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
