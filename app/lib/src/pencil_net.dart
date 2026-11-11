/// The small digit network that reads a pencilled page number: a plain MLP
/// (ReLU, softmax), float64 like `book_guard/_pencil_net.py`. Its weights file,
/// `assets/pencil_digits.bin`, is the PC's: little-endian `PNCL`, u32 layer
/// count n, n + 1 u32 sizes, then per layer `out x in` weights row by row and
/// `out` biases, all float32. No plugin, no ML Kit.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The network.
class PencilNet {
  const new _(this._weights, this._biases, this._sizes);

  /// Parses the weights file's bytes; throws [FormatException] if it is not
  /// one.
  factory parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 8 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'PNCL') {
      throw const FormatException('not a pencil-digit weights file');
    }
    final count = data.getUint32(4, Endian.little);
    final sizes = [
      for (var i = 0; i <= count; i++) data.getUint32(8 + 4 * i, Endian.little),
    ];
    var offset = (3 + count) * 4;
    final weights = <Float64List>[];
    final biases = <Float64List>[];
    for (var i = 0; i < count; i++) {
      final w = Float64List(sizes[i + 1] * sizes[i]);
      for (var k = 0; k < w.length; k++, offset += 4) {
        w[k] = data.getFloat32(offset, Endian.little);
      }
      final b = Float64List(sizes[i + 1]);
      for (var k = 0; k < b.length; k++, offset += 4) {
        b[k] = data.getFloat32(offset, Endian.little);
      }
      weights.add(w);
      biases.add(b);
    }
    return PencilNet._(weights, biases, sizes);
  }

  final List<Float64List> _weights;
  final List<Float64List> _biases;
  final List<int> _sizes;

  /// Softmax over the classes (ten digits, then "not a digit") for one 28x28
  /// picture, row-major.
  List<double> probabilities(List<double> picture) {
    var x = Float64List.fromList(picture);
    for (var layer = 0; layer < _weights.length; layer++) {
      final fanIn = _sizes[layer];
      final out = Float64List(_sizes[layer + 1]);
      for (var o = 0; o < out.length; o++) {
        var sum = _biases[layer][o];
        for (var i = 0; i < fanIn; i++) {
          sum += _weights[layer][o * fanIn + i] * x[i];
        }
        out[o] = layer < _weights.length - 1 && sum < 0 ? 0 : sum;
      }
      x = out;
    }
    final top = x.reduce(math.max);
    final e = [for (final v in x) math.exp(v - top)];
    final total = e.fold<double>(0, (a, b) => a + b);
    return [for (final v in e) v / total];
  }
}
