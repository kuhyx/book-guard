import 'package:book_guard_app/src/page_prep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _paper(int w, int h, {int tone = 200}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(tone, tone, tone));
  return image;
}

/// The pixel-level work around the native recogniser is plain Dart.
void main() {
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
    final inkSizes = [
      for (final jpeg in prepared.inks)
        (img.decodeJpg(jpeg)!.width, img.decodeJpg(jpeg)!.height),
    ];
    expect(inkSizes, sizes);
  });

  test('big photos are downscaled; no EXIF means orientation 1', () {
    final prepared = preparePage(
      img.encodeJpg(img.Image(width: 3200, height: 2400)),
    );
    expect(prepared.orientation, 1);
    expect((prepared.width, prepared.height), (1600, 1200));
    expect(prepared.scale, 0.5);
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
    final flat = img.decodeJpg(flatten(page))!;
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
    final flat = img.decodeJpg(flatten(page))!;
    expect(flat.getPixel(72, 72).r, greaterThan(240));
  });

  test('a tiny image still flattens', () {
    final flat = img.decodeJpg(flatten(_paper(3, 3)))!;
    expect((flat.width, flat.height), (3, 3));
  });

  test('a box is cropped with a margin, turned like its page, flattened', () {
    final bytes = img.encodeJpg(_paper(100, 100));
    const box = (left: 40, top: 40, right: 60, bottom: 50);
    final upright = img.decodeJpg(cropForBox((bytes, box, 0)))!;
    expect((upright.width, upright.height), (30, 20));
    final turned = img.decodeJpg(cropForBox((bytes, box, 90)))!;
    expect((turned.width, turned.height), (20, 30));
    const edge = (left: 0, top: 0, right: 10, bottom: 10);
    final clipped = img.decodeJpg(cropForBox((bytes, edge, 0)))!;
    expect((clipped.width, clipped.height), (13, 13));
  });

  test('the edge strips are cut into overlapping windows', () {
    final windows = edgeWindows((img.encodeJpg(_paper(2600, 1300)), 0));
    // 2600 wide: windows at 0, 500, 1000, 1500, 2000 (a 600 px tail).
    expect(
      [for (final w in windows) w.left],
      [
        0, 500, 1000, 1500, 2000, //
        0, 500, 1000, 1500, 2000,
      ],
    );
    expect(windows.map((w) => w.workWidth).toSet(), {2600});
    // Band = 22% of 1300 = 286 px; the bottom one starts at 1300 - 286.
    expect([windows.first.top, windows.last.top], [0, 1014]);
    final tail = img.decodeJpg(windows[4].jpeg)!;
    expect((tail.width, tail.height), (600, 286));
  });

  test('a narrow page is one window per strip; big photos are shrunk', () {
    final narrow = edgeWindows((img.encodeJpg(_paper(300, 400)), 90));
    expect(narrow.map((w) => w.left), [0, 0]);
    expect(narrow.first.workWidth, 400);
    final big = edgeWindows((img.encodeJpg(_paper(6400, 3200)), 0));
    expect(big.first.workWidth, 3200);
  });
}
