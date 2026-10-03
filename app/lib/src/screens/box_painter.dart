import 'package:flutter/material.dart';

/// The review screen's boxes: every number found (thin), the chosen one
/// (thick) and the box being drawn.
class ReviewBoxPainter extends CustomPainter {
  /// Creates the painter.
  const new({
    required this.others,
    required this.chosen,
    required this.drawing,
    required this.chosenColor,
    required this.otherColor,
  });

  /// Every number found.
  final List<Rect> others;

  /// The chosen number.
  final Rect? chosen;

  /// The box being drawn.
  final Rect? drawing;

  /// Colour of [chosen] and [drawing].
  final Color chosenColor;

  /// Colour of [others].
  final Color otherColor;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = otherColor;
    final thick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = chosenColor;
    for (final rect in others) {
      canvas.drawRect(rect.inflate(6), thin);
    }
    if (chosen case final rect?) canvas.drawRect(rect.inflate(8), thick);
    if (drawing case final rect?) canvas.drawRect(rect, thick);
  }

  @override
  bool shouldRepaint(ReviewBoxPainter old) =>
      old.chosen != chosen || old.drawing != drawing || old.others != others;
}
