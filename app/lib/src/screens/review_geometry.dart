import 'dart:math' as math;

import 'package:book_guard_app/src/page_number.dart';
import 'package:material_ui/material_ui.dart';

/// A drag on the preview (logical px) as a box in the stored file's pixels
/// at scale [factor]; null when it is too small to hold a number.
Box? pixelBox(Offset a, Offset b, double factor) {
  final box = (
    left: (math.min(a.dx, b.dx) / factor).floor(),
    top: (math.min(a.dy, b.dy) / factor).floor(),
    right: (math.max(a.dx, b.dx) / factor).ceil(),
    bottom: (math.max(a.dy, b.dy) / factor).ceil(),
  );
  return box.right - box.left < 4 || box.bottom - box.top < 4 ? null : box;
}

/// [box] (preview pixels) on screen at scale [factor].
Rect boxRect(Box box, double factor) => Rect.fromLTRB(
  box.left * factor,
  box.top * factor,
  box.right * factor,
  box.bottom * factor,
);

/// The rectangle being dragged, if a drag is under way.
Rect? dragRect((Offset?, Offset?) drag) => drag.$1 == null || drag.$2 == null
    ? null
    : Rect.fromPoints(drag.$1!, drag.$2!);
