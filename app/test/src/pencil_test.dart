import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:book_guard_app/src/pencil.dart';
import 'package:book_guard_app/src/pencil_blob.dart';
import 'package:book_guard_app/src/pencil_norm.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The PC's answers (written by `python3 -m scripts.pencil_goldens`): the
/// Dart port must read the same numbers from the same pixels, and the same
/// pictures and probabilities from the same glyph masks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final goldens = jsonDecode(
    File('test/fixtures/pencil_goldens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final weights = File('assets/pencil_digits.bin').readAsBytesSync();
  final net = PencilNet.parse(weights);
  final cases = (goldens['cases'] as List).cast<Map<String, dynamic>>();

  test('the weights are the ones the fixture was made with', () {
    expect(sha256.convert(weights).toString(), goldens['weights_sha256']);
  });

  test('every golden page reads as the PC reads it', () {
    for (final c in cases) {
      final gray = Uint8List.fromList(
        zlib.decode(base64Decode(c['gray'] as String)),
      );
      final body = (c['body'] as List).cast<int>();
      final got = readPencilPage(
        net,
        gray,
        c['width'] as int,
        c['height'] as int,
        body: (
          left: body[0],
          top: body[1],
          right: body[2],
          bottom: body[3],
          line: (c['line'] as num).toDouble(),
        ),
      );
      expect(got, c['expected'], reason: c['name'] as String);
    }
  });

  test('a glyph mask normalises and classifies as on the PC', () {
    var seen = 0;
    for (final c in cases) {
      for (final m in (c['masks'] as List).cast<Map<String, dynamic>>()) {
        final rows = (m['mask'] as List).cast<String>();
        final mask = Mask(rows.length, rows.first.length);
        for (var y = 0; y < rows.length; y++) {
          for (var x = 0; x < rows[y].length; x++) {
            if (rows[y][x] == '1') mask.cells[y * mask.width + x] = 1;
          }
        }
        final picture = normalise(mask, 0.14);
        final want = (m['picture'] as List).cast<num>();
        for (var i = 0; i < want.length; i++) {
          expect(picture[i], closeTo(want[i], 1e-6), reason: 'pixel $i');
        }
        final probs = (m['probs'] as List).cast<List<dynamic>>();
        const fracs = [0.11, 0.14, 0.18];
        for (var f = 0; f < fracs.length; f++) {
          final got = net.probabilities(normalise(mask, fracs[f]));
          for (var k = 0; k < got.length; k++) {
            expect(got[k], closeTo(probs[f][k] as num, 1e-6));
          }
        }
        seen++;
      }
    }
    expect(seen, greaterThan(5));
  });

  test('the shipped asset loads', () async {
    final loaded = await loadPencilNet();
    expect(loaded.probabilities(List.filled(784, 0)).length, 11);
  });

  test('a text box outside the page is clipped, or gives nothing', () {
    final gray = Uint8List(200 * 300)..fillRange(0, 200 * 300, 200);
    int? read(int l, int t, int r, int b) => readPencilPage(
      net,
      gray,
      200,
      300,
      body: (left: l, top: t, right: r, bottom: b, line: 16),
    );
    expect(read(20, 40, 180, 9000), isNull);
    expect(read(5000, 40, 6000, 100), isNull);
    expect(read(20, 5000, 180, 6000), isNull);
  });

  test('a file that is not weights is refused', () {
    expect(
      () => PencilNet.parse(Uint8List.fromList(List.filled(40, 7))),
      throwsFormatException,
    );
  });

  test('stroke width, thickening and squeezing', () {
    final bar = Mask(40, 3, Uint8List(120)..fillRange(0, 120, 1));
    expect(strokeWidth(bar), closeTo(2 * 120 / 82, 1e-9));
    expect(strokeWidth(Mask(9, 4)), 9);
    final dot = Mask(5, 5)..cells[12] = 1;
    expect(thicken(dot, 0), same(dot));
    expect(thicken(dot, 1).area, 9);
    final two = Mask(1, 2, Uint8List.fromList([1, 0]));
    expect(squeeze(two, 2, 4), [1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0]);
    expect(recentre(List.filled(pencilField * pencilField, 0)).length, 784);
  });

  test('blobs drop dust and edges, patches join, glyphs merge', () {
    const w = 120;
    final ink = Uint8List(80 * w);
    void rect(int l, int t, int r, int b) {
      for (var y = t; y <= b; y++) {
        for (var x = l; x <= r; x++) {
          ink[y * w + x] = 1;
        }
      }
    }

    rect(20, 20, 20, 21); // dust
    rect(0, 30, 5, 40); // touches the edge
    rect(60, 50, 63, 62); // a glyph
    final found = blobs(
      ink,
      w,
      (top: 0, bottom: 80, left: 0, right: w),
      10,
      0.5,
    );
    expect(found.map((b) => b.box.left), [60]);
    expect(
      blobs(ink, w, (top: 0, bottom: 80, left: 0, right: w), 10, 0.0001),
      isEmpty,
    );
    const a = Blob(Box(10, 10, 14, 30), [], []);
    const b = Blob(Box(22, 12, 26, 30), [], []);
    const far = Blob(Box(100, 10, 104, 30), [], []);
    expect(patches([a, b, far], 10).map((p) => p.$2.length), [2, 1]);
    const bar = Blob(Box(10, 10, 30, 12), [], []);
    const stem = Blob(Box(18, 14, 22, 40), [], []);
    expect(mergeGlyphs([far, stem, bar]).map((g) => g.left), [10, 100]);
  });
}
