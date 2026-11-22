/// The pixel work before Tesseract: a photo decoded once, downscaled,
/// flattened (paper tone and shadows taken out, as the PC's `_ocr.flatten`
/// does) and turned as the reader asks. Crops and edge strips: page_crops.
///
/// Everything here is plain Dart and runs inside `Isolate.run`.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const _edge = 1600;

// Flatten: the paper is the heavily blurred picture; ink is what is darker.
const _bgShrink = 8;
const _bgBlur = 4;
const _inkGain = 3;
// Ink fainter than this (after the gain) is JPEG noise, and Tesseract reads
// noise as text -- slowly: a black photo took 33 s.
const _noiseFloor = 24;

/// The photo decoded once (off the UI thread) and downscaled. It is
/// flattened once; each turn is that ink turned ([turnGray]): the camera's EXIF
/// turn is wrong when it points straight down at a book (the p. 51 photo of
/// 2026-10-03), but most photos read on the first turn tried.
class Prepared {
  /// Creates the prepared photo.
  const new({
    required this.orientation,
    required this.storedWidth,
    required this.storedHeight,
    required this.width,
    required this.height,
    required this.scale,
    required this.small,
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

  /// The downscaled, EXIF-applied image, not turned.
  final img.Image small;
}

int _orientation(Uint8List bytes) =>
    img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;

/// A one-channel picture, `pixels` row by row (Tesseract gets it as
/// [inkJpeg]: handed raw, it missed small page numbers it reads as JPEG).
typedef Gray = ({Uint8List pixels, int width, int height});

/// [source] as dark ink on white: darker-than-paper times a gain.
Gray flatten(img.Image source) {
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
  return (pixels: ink, width: w, height: h);
}

/// [ink] as the q92 three-channel JPEG Tesseract was once handed.
Uint8List inkJpeg(Gray ink) => img.encodeJpg(
  img.Image.fromBytes(
    width: ink.width,
    height: ink.height,
    bytes: ink.pixels.buffer,
    numChannels: 1,
  ).convert(numChannels: 3),
  quality: 92,
);

/// The job's picture turned by its degrees clockwise, as `img.copyRotate`
/// turns it.
Gray turnGray((Gray, int) job) {
  final (gray, turn) = job;
  if (turn == 0) return gray;
  final turned = img.copyRotate(
    img.Image.fromBytes(
      width: gray.width,
      height: gray.height,
      bytes: gray.pixels.buffer,
      numChannels: 1,
    ),
    angle: turn,
  );
  return (
    pixels: turned.getBytes(),
    width: turned.width,
    height: turned.height,
  );
}

/// A photo ready for the reader: [Prepared], the ink of its first turn,
/// and the full-resolution picture crops and edge strips are cut from.
typedef PreparedPhoto = (Prepared, Gray, img.Image);

/// Decodes [bytes] once (EXIF applied), downscales and flattens it.
PreparedPhoto preparePhoto(Uint8List bytes) {
  final orientation = _orientation(bytes);
  final decoded = img.decodeJpg(bytes)!;
  final sideways = orientation >= 5 && orientation <= 8;
  final scale = math.min(1, _edge / math.max(decoded.width, decoded.height));
  final small = img.copyResize(
    decoded,
    width: (decoded.width * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final prepared = Prepared(
    orientation: orientation,
    storedWidth: sideways ? decoded.height : decoded.width,
    storedHeight: sideways ? decoded.width : decoded.height,
    width: small.width,
    height: small.height,
    scale: small.width / decoded.width,
    small: small,
  );
  return (prepared, flatten(small), decoded);
}

/// The job's downscaled image turned by its degrees, as the preview JPEG.
Uint8List previewFor((img.Image, int) job) =>
    img.encodeJpg(img.copyRotate(job.$1, angle: job.$2), quality: 90);
