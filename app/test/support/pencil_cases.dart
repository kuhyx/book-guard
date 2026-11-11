import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:book_guard_app/src/pencil.dart';
import 'package:image/image.dart' as img;

/// A golden margin crop (`test/fixtures/pencil_goldens.json`) as a gray
/// JPEG photo, with where its text sits.
(Uint8List, PencilBody) pencilCaseJpeg(String name) {
  final goldens = jsonDecode(
    File('test/fixtures/pencil_goldens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final c = (goldens['cases'] as List).cast<Map<String, dynamic>>().firstWhere(
    (c) => c['name'] == name,
  );
  final gray = zlib.decode(base64Decode(c['gray'] as String));
  final width = c['width'] as int;
  final image = img.Image(width: width, height: c['height'] as int);
  for (var i = 0; i < gray.length; i++) {
    image.setPixelRgb(i % width, i ~/ width, gray[i], gray[i], gray[i]);
  }
  final b = (c['body'] as List).cast<int>();
  return (
    img.encodeJpg(image, quality: 92),
    (
      left: b[0],
      top: b[1],
      right: b[2],
      bottom: b[3],
      line: (c['line'] as num).toDouble(),
    ),
  );
}
