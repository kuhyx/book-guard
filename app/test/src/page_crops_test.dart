import 'package:book_guard_app/src/page_crops.dart';
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

/// Full-resolution cuts: number crops and edge-strip windows.
void main() {
  test('a box is cropped with a margin, turned like its page, flattened', () {
    final bytes = img.encodeJpg(_paper(100, 100));
    const box = (left: 40, top: 40, right: 60, bottom: 50);
    final upright = _img(cropFromJpeg((bytes, box, 0)));
    expect((upright.width, upright.height), (30, 20));
    final turned = _img(cropFromJpeg((bytes, box, 90)));
    expect((turned.width, turned.height), (20, 30));
    const edge = (left: 0, top: 0, right: 10, bottom: 10);
    final clipped = _img(cropFromJpeg((bytes, edge, 0)));
    expect((clipped.width, clipped.height), (13, 13));
  });

  test('the edge strips are cut into overlapping windows', () {
    final windows = edgeWindows((_paper(2600, 1300), 0));
    // 2600 wide: windows at 0, 500, 1000, 1500, 2000 (a 600 px tail).
    expect(
      [for (final EdgeWindow w in windows) w.left],
      [
        0, 500, 1000, 1500, 2000, //
        0, 500, 1000, 1500, 2000,
      ],
    );
    expect(windows.map((w) => w.workWidth).toSet(), {2600});
    // Band = 22% of 1300 = 286 px; the bottom one starts at 1300 - 286.
    expect([windows.first.top, windows.last.top], [0, 1014]);
    final tail = _img(windows[4].ink);
    expect((tail.width, tail.height), (600, 286));
  });

  test('a narrow page is one window per strip; big photos are shrunk', () {
    final narrow = edgeWindows((_paper(300, 400), 90));
    expect(narrow.map((w) => w.left), [0, 0]);
    expect(narrow.first.workWidth, 400);
    final big = edgeWindows((_paper(6400, 3200), 0));
    expect(big.first.workWidth, 3200);
  });
}
