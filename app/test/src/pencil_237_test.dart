import 'dart:io';
import 'dart:typed_data';

import 'package:book_guard_app/src/pencil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// 2026-11-21: a chapter opener ("14 / Secularism", no printed page number)
// with 237 pencilled at the top right. Tesseract read it as 234; the phone's
// digit net (this port of `_pencil_find.py`) must read 237. The page is the
// PC test's own pixels (`test_a_pencilled_237_over_a_chapter_heading_is_read`
// pins `test/fixtures/pencil_237.png` to them).

Uint8List _gray(img.Image image) {
  final gray = Uint8List(image.width * image.height);
  var at = 0;
  for (final p in image) {
    gray[at++] = p.r.toInt();
  }
  return gray;
}

void main() {
  final net = PencilNet.parse(
    File('assets/pencil_digits.bin').readAsBytesSync(),
  );
  final page = img.decodePng(
    File('test/fixtures/pencil_237.png').readAsBytesSync(),
  )!;
  const body = (left: 100, top: 300, right: 700, bottom: 600, line: 16.0);

  test('a pencilled 237 over a printed chapter heading reads 237', () {
    expect(
      readPencilPage(net, _gray(page), page.width, page.height, body: body),
      237,
    );
  });

  test('the printed heading alone is no pencilled number', () {
    final heading = img.Image.from(page);
    img.fillRect(
      heading,
      x1: 540,
      y1: 90,
      x2: 630,
      y2: 150,
      color: img.ColorUint8.rgb(200, 200, 200),
    );
    expect(
      readPencilPage(
        net,
        _gray(heading),
        heading.width,
        heading.height,
        body: body,
      ),
      isNull,
    );
  });
}
