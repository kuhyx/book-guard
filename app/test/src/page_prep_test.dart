import 'package:book_guard_app/src/page_prep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _img(Gray g) => img.Image.fromBytes(
  width: g.width,
  height: g.height,
  bytes: g.pixels.buffer,
  numChannels: 1,
);

img.Image _paper(int w, int h, {int tone = 200}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(tone, tone, tone));
  return image;
}

/// The pixel-level work around the native recogniser is plain Dart.
void main() {
  test('a photo is decoded once, EXIF applied, turned on demand', () {
    final stored = img.Image(width: 80, height: 40);
    stored.exif.imageIfd.orientation = 6;
    final (prepared, ink, decoded) = preparePhoto(img.encodeJpg(stored));
    expect(prepared.orientation, 6);
    expect((prepared.storedWidth, prepared.storedHeight), (80, 40));
    expect((prepared.width, prepared.height, prepared.scale), (40, 80, 1.0));
    expect((decoded.width, decoded.height), (40, 80));
    const turns = [0, 90, 180, 270];
    final sizes = [
      for (final turn in turns)
        if (img.decodeJpg(previewFor((prepared.small, turn))) case final jpeg?)
          (jpeg.width, jpeg.height),
    ];
    expect(sizes, [(40, 80), (80, 40), (40, 80), (80, 40)]);
    final inkSizes = [
      for (final turn in turns)
        if (turnGray((ink, turn)) case final g) (g.width, g.height),
    ];
    expect(inkSizes, sizes);
    final jpeg = img.decodeJpg(inkJpeg(ink))!;
    expect((jpeg.width, jpeg.height, jpeg.numChannels), (40, 80, 3));
  });

  test('big photos are downscaled; no EXIF means orientation 1', () {
    final (prepared, ink, decoded) = preparePhoto(
      img.encodeJpg(img.Image(width: 3200, height: 2400)),
    );
    expect(prepared.orientation, 1);
    expect((prepared.width, prepared.height), (1600, 1200));
    expect((ink.width, ink.height), (1600, 1200));
    expect(prepared.scale, 0.5);
    expect(decoded.width, 3200);
  });

  test('flatten keeps ink dark and takes the paper to white', () {
    final page = _paper(160, 160);
    img.fillRect(
      page,
      x1: 70,
      y1: 70,
      x2: 74,
      y2: 90,
      color: img.ColorRgb8(150, 150, 150),
    );
    final flat = _img(flatten(page));
    expect(flat.getPixel(10, 10).r, greaterThan(240));
    expect(flat.getPixel(72, 80).r, lessThan(120));
  });

  test('faint speckle is not ink', () {
    final page = _paper(160, 160);
    img.fillRect(
      page,
      x1: 70,
      y1: 70,
      x2: 74,
      y2: 74,
      color: img.ColorRgb8(194, 194, 194),
    );
    final flat = _img(flatten(page));
    expect(flat.getPixel(72, 72).r, greaterThan(240));
  });

  test('a tiny image still flattens', () {
    final flat = _img(flatten(_paper(3, 3)));
    expect((flat.width, flat.height), (3, 3));
  });
}
