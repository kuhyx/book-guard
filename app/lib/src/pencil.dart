/// The API of the pencil-number reader: what the keypad calls to pre-fill a
/// page number pencilled in the margin of a photo with no printed one.
///
/// Never an acceptance: the answer only fills the keypad the user confirms.
/// Call it only when the printed-number reader found nothing. null is the
/// answer to anything doubtful, a lone "1" most of all.
library;

import 'dart:typed_data';

import 'package:book_guard_app/src/pencil_find.dart';
import 'package:book_guard_app/src/pencil_net.dart';
import 'package:flutter/services.dart' show rootBundle;

export 'package:book_guard_app/src/pencil_net.dart' show PencilNet;

/// Where the page's text sits, in the pixels of the gray image given to
/// [readPencilPage].
typedef PencilBody = ({int left, int top, int right, int bottom, double line});

/// The shipped network (`assets/pencil_digits.bin`, the PC's own file).
Future<PencilNet> loadPencilNet() async {
  final data = await rootBundle.load('assets/pencil_digits.bin');
  return PencilNet.parse(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// The pencilled page number in the margin of the upright page, or null.
///
/// [gray] is the upright photo as 8-bit gray, row by row ([width] x
/// [height]); [body] is where its confidently read text sits (the box of the
/// main text column -- not a facing page's -- and the text-line height, all
/// in those pixels), which the margin is measured from.
int? readPencilPage(
  PencilNet net,
  Uint8List gray,
  int width,
  int height, {
  required PencilBody body,
}) => findPencilNumber(net, gray, width, height, (
  left: body.left,
  top: body.top,
  right: body.right,
  bottom: body.bottom,
), body.line);
