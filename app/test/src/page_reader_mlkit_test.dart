import 'package:book_guard_app/src/page_reader.dart' as api;
import 'package:book_guard_app/src/page_reader_mlkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The recogniser itself is native and checked on the phone
/// (`self_test_io.dart`); the pixel work around it is plain Dart.
void main() {
  test('the platform reader is ML Kit', () {
    expect(api.createPageReader(), isA<MlKitPageReader>());
  });

  test('a photo is decoded once, EXIF applied, in all four turns', () {
    final stored = img.Image(width: 80, height: 40);
    stored.exif.imageIfd.orientation = 6;
    final prepared = preparePage(img.encodeJpg(stored));
    expect(prepared.orientation, 6);
    expect((prepared.storedWidth, prepared.storedHeight), (80, 40));
    expect((prepared.width, prepared.height, prepared.scale), (40, 80, 1.0));
    final sizes = [
      for (final jpeg in prepared.jpegs)
        (img.decodeJpg(jpeg)!.width, img.decodeJpg(jpeg)!.height),
    ];
    expect(sizes, [(40, 80), (80, 40), (40, 80), (80, 40)]);
  });

  test('big photos are downscaled; no EXIF means orientation 1', () {
    final prepared = preparePage(
      img.encodeJpg(img.Image(width: 3200, height: 2400)),
    );
    expect(prepared.orientation, 1);
    expect((prepared.width, prepared.height), (1600, 1200));
    expect(prepared.scale, 0.5);
  });

  test('a box is cropped with a margin and turned like its page', () {
    final bytes = img.encodeJpg(img.Image(width: 100, height: 100));
    const box = (left: 40, top: 40, right: 60, bottom: 50);
    final upright = img.decodeJpg(cropForBox((bytes, box, 0)))!;
    expect((upright.width, upright.height), (30, 20));
    final turned = img.decodeJpg(cropForBox((bytes, box, 90)))!;
    expect((turned.width, turned.height), (20, 30));
    const edge = (left: 0, top: 0, right: 10, bottom: 10);
    final clipped = img.decodeJpg(cropForBox((bytes, edge, 0)))!;
    expect((clipped.width, clipped.height), (13, 13));
  });
}
