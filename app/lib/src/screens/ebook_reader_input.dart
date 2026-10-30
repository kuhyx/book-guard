import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The reader's controls, none of them drawn: a tap on the right ~40% of
/// the screen is the next screenful and on the left ~40% the previous one
/// (the middle does nothing); volume down / up page the same way, and on
/// a keyboard ArrowDown / PageDown / Space and ArrowUp / PageUp; a
/// right-to-left fling or Escape closes the reader.
///
/// Volume keys: Flutter's Android embedding hands every key to the
/// framework first (`FlutterView.dispatchKeyEvent` ->
/// `KeyboardManager.handleEvent`) and gives it back to the system -- which
/// would change the volume -- only when no handler claimed it. So
/// returning [KeyEventResult.handled] here, for down, repeat and up, is
/// what keeps the volume where it is; no native override is needed.
class ReaderInput extends StatefulWidget {
  /// Creates the controls around [child].
  const new({
    required this.onNext,
    required this.onPrevious,
    required this.onExit,
    required this.child,
    super.key,
  });

  /// The next screenful.
  final VoidCallback onNext;

  /// The previous screenful.
  final VoidCallback onPrevious;

  /// Close the reader.
  final VoidCallback onExit;

  /// The text.
  final Widget child;

  /// The share of the width, from each side, that a tap pages in.
  static const tapZone = 0.4;

  /// A close fling is at least this fast to the left (logical px/s) ...
  static const exitVelocity = 600.0;

  /// ... and travels at least this far, so a sloppy vertical scroll that
  /// drifts sideways never closes the book.
  static const exitDistance = 64.0;

  @override
  State<ReaderInput> createState() => _ReaderInputState();
}

class _ReaderInputState extends State<ReaderInput> {
  static final Set<LogicalKeyboardKey> _next = {
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.space,
  };
  static final Set<LogicalKeyboardKey> _previous = {
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageUp,
  };

  double _dragged = 0;

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final act = event is KeyDownEvent || event is KeyRepeatEvent;
    if (_next.contains(key)) {
      if (act) widget.onNext();
    } else if (_previous.contains(key)) {
      if (act) widget.onPrevious();
    } else if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.onExit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _tap(TapUpDetails tap) {
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    final x = tap.localPosition.dx / width;
    if (x >= 1 - ReaderInput.tapZone) {
      widget.onNext();
    } else if (x <= ReaderInput.tapZone) {
      widget.onPrevious();
    }
  }

  void _dragEnd(DragEndDetails end) {
    final velocity = end.primaryVelocity ?? 0;
    if (velocity <= -ReaderInput.exitVelocity &&
        _dragged <= -ReaderInput.exitDistance) {
      widget.onExit();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _tap,
      onHorizontalDragStart: (_) => _dragged = 0,
      onHorizontalDragUpdate: (drag) => _dragged += drag.delta.dx,
      onHorizontalDragEnd: _dragEnd,
      dragStartBehavior: DragStartBehavior.down,
      child: widget.child,
    ),
  );
}
