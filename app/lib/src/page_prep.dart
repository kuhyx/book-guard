/// The pixel work before Tesseract: a photo decoded once, downscaled, turned
/// four ways and flattened (paper tone and shadows taken out, as the PC's
/// `_ocr.flatten` does), plus the full-resolution strips near the page's top
/// and bottom edge where a small lone page number is found.
///
/// Everything here is plain Dart and runs inside `Isolate.run`.
library;

import 'dart:math' as math;

import 'package:book_guard_app/src/page_number.dart' show Box;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const _edge = 1600;
const _turns = [0, 90, 180, 270];
const _boxPad = 0.25;

// Flatten: the paper is the heavily blurred picture; ink is what is darker.
const _bgShrink = 8;
const _bgBlur = 4;
const _inkGain = 3;
// Ink fainter than this (after the gain) is JPEG noise, and Tesseract reads
// noise as text -- slowly: a black photo took 33 s.
const _noiseFloor = 24;

// Edge strips: the outer fifth (and a little more) of the upright page, at
// up to _workEdge pixels, cut into windows Tesseract can still lay out (a
// whole noisy strip makes it see nothing -- the lone "7" of p7_start).
const _bandFrac = 0.22;
const _workEdge = 3200;
const _windowWidth = 1000;
const _windowStep = 500;

/// The photo decoded once (off the UI thread), downscaled, in all four
/// orientations -- the camera's EXIF turn is wrong when it points straight
/// down at a book (the p. 51 photo of 2026-10-03).
class Prepared {
  /// Creates the prepared photo.
  const new({
    required this.orientation,
    required this.storedWidth,
    required this.storedHeight,
    required this.width,
    required this.height,
    required this.scale,
    required this.jpegs,
    required this.inks,
  });

  /// The file's EXIF orientation (1 if none).
  final int orientation;

  /// The stored pixels' width, before EXIF.
  final int storedWidth;

  /// The stored pixels' height, before EXIF.
  final int storedHeight;

  /// The downscaled, EXIF-applied image's width, before any turn.
  final int width;

  /// The downscaled, EXIF-applied image's height, before any turn.
  final int height;

  /// downscaled / decoded.
  final double scale;

  /// One JPEG per turn: 0, 90, 180, 270 degrees clockwise.
  final List<Uint8List> jpegs;

  /// The same turns, flattened to dark ink on white, for Tesseract.
  final List<Uint8List> inks;
}

/// A strip of the upright page for Tesseract: [jpeg] cut at ([left], [top])
/// of a page that is [workWidth] pixels wide.
class EdgeWindow {
  /// Creates a window.
  const new(this.jpeg, this.left, this.top, this.workWidth);

  /// The flattened strip.
  final Uint8List jpeg;

  /// Its left edge on the page, in working pixels.
  final int left;

  /// Its top edge on the page, in working pixels.
  final int top;

  /// The page's width in working pixels (the unit of [left] and [top]).
  final int workWidth;
}

int _orientation(Uint8List bytes) =>
    img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;

/// [source] as dark ink on white: darker-than-paper times a gain, as a
/// one-channel JPEG.
@visibleForTesting
Uint8List flatten(img.Image source) {
  final rgb = source
      .convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  final w = source.width;
  final h = source.height;
  final gray = Uint8List(w * h);
  for (var i = 0; i < gray.length; i++) {
    gray[i] =
        (rgb[3 * i] * 0.299 + rgb[3 * i + 1] * 0.587 + rgb[3 * i + 2] * 0.114)
            .round();
  }
  final small = img.copyResize(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: gray.buffer,
      numChannels: 1,
    ),
    width: math.max(1, w ~/ _bgShrink),
    interpolation: img.Interpolation.average,
  );
  final paper = img
      .copyResize(
        img.gaussianBlur(small, radius: _bgBlur),
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      )
      .getBytes();
  final ink = Uint8List(w * h);
  for (var i = 0; i < ink.length; i++) {
    final dark = math.max(0, paper[i] - gray[i]) * _inkGain;
    ink[i] = 255 - (dark < _noiseFloor ? 0 : math.min(255, dark));
  }
  return img.encodeJpg(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: ink.buffer,
      numChannels: 1,
    ).convert(numChannels: 3),
    quality: 92,
  );
}

/// Decodes [bytes] once, downscaled, in all four turns.
Prepared preparePage(Uint8List bytes) {
  final orientation = _orientation(bytes);
  final decoded = img.decodeJpg(bytes)!;
  final sideways = orientation >= 5 && orientation <= 8;
  final scale = math.min(1, _edge / math.max(decoded.width, decoded.height));
  final small = img.copyResize(
    decoded,
    width: (decoded.width * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final turned = [
    for (final turn in _turns) img.copyRotate(small, angle: turn),
  ];
  return Prepared(
    orientation: orientation,
    storedWidth: sideways ? decoded.height : decoded.width,
    storedHeight: sideways ? decoded.width : decoded.height,
    width: small.width,
    height: small.height,
    scale: small.width / decoded.width,
    jpegs: [for (final t in turned) img.encodeJpg(t, quality: 90)],
    inks: [for (final t in turned) flatten(t)],
  );
}

/// The full-resolution crop around the job's box (decoded pixels), turned
/// like the page it was drawn on and flattened.
Uint8List cropForBox((Uint8List, Box, int) job) {
  final (bytes, box, turn) = job;
  final decoded = img.decodeJpg(bytes)!;
  final pad = (math.max(box.right - box.left, box.bottom - box.top) * _boxPad)
      .round();
  final left = math.max(0, box.left - pad);
  final top = math.max(0, box.top - pad);
  final crop = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: math.min(decoded.width, box.right + pad) - left,
    height: math.min(decoded.height, box.bottom + pad) - top,
  );
  return flatten(img.copyRotate(crop, angle: turn));
}

img.Image _band(img.Image page, {required bool top}) {
  final height = (page.height * _bandFrac).round();
  return img.copyCrop(
    page,
    x: 0,
    y: top ? 0 : page.height - height,
    width: page.width,
    height: height,
  );
}

/// The top and bottom strips of a photo turned by the job's degrees,
/// flattened and cut into overlapping windows.
List<EdgeWindow> edgeWindows((Uint8List, int) job) {
  final (bytes, turn) = job;
  final decoded = img.decodeJpg(bytes)!;
  final scale = math.min(
    1,
    _workEdge / math.max(decoded.width, decoded.height),
  );
  final page = img.copyRotate(
    img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      interpolation: img.Interpolation.average,
    ),
    angle: turn,
  );
  final windows = <EdgeWindow>[];
  for (final topStrip in [true, false]) {
    final band = _band(page, top: topStrip);
    final top = topStrip ? 0 : page.height - band.height;
    var left = 0;
    while (true) {
      final width = math.min(_windowWidth, band.width - left);
      windows.add(
        EdgeWindow(
          flatten(
            img.copyCrop(
              band,
              x: left,
              y: 0,
              width: width,
              height: band.height,
            ),
          ),
          left,
          top,
          page.width,
        ),
      );
      if (left + width >= band.width) break;
      left += _windowStep;
    }
  }
  return windows;
}
