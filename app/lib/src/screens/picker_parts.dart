import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// `7` -> `07`.
String pad2(int n) => n.toString().padLeft(2, '0');

/// The close and check icons at the foot of every icon picker. The words
/// are spoken only (`semanticLabel`), never painted.
List<Widget> pickerActions(BuildContext context, VoidCallback onConfirm) => [
  IconButton(
    onPressed: () => Navigator.of(context).pop(),
    icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
  ),
  IconButton.filled(
    onPressed: onConfirm,
    icon: const Icon(Icons.check, semanticLabel: 'OK'),
  ),
];

/// A looping wheel of `00`..`count - 1`. Touch or mouse drag and fling it,
/// turn the mouse wheel (one step per notch) or tap a neighbouring numeral.
class NumberWheel extends StatefulWidget {
  /// Creates a wheel showing [value].
  const new({
    required this.count,
    required this.value,
    required this.onChanged,
    this.spoken = '',
    super.key,
  });

  /// How many values: 24 for hours, 60 for minutes.
  final int count;

  /// The value it starts on.
  final int value;

  /// Called with the value at the centre whenever it changes.
  final ValueChanged<int> onChanged;

  /// Spoken only: what the wheel picks.
  final String spoken;

  /// The height of one numeral's slot.
  static const double itemExtent = 40;

  @override
  State<NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<NumberWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The shortest way round to [value]: no lap of the wheel for a neighbour.
  void _toValue(int value) {
    var by = (value - _controller.selectedItem) % widget.count;
    if (by > widget.count ~/ 2) by -= widget.count;
    if (by == 0) return;
    _controller.animateToItem(
      _controller.selectedItem + by,
      duration: AppDuration.fast,
      curve: Curves.easeOut,
    );
  }

  /// One step per notch, registered from the numeral (hit before the
  /// scrollable, so it wins over a pixel scroll of several items). A jump,
  /// not an animation: while the wheel animates its numerals ignore the
  /// pointer, and a quick second notch would be lost to the scrollable.
  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _controller.jumpToItem(
        _controller.selectedItem + (event.scrollDelta.dy > 0 ? 1 : -1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall;
    return Semantics(
      label: widget.spoken,
      child: SizedBox(
        width: 64,
        height: NumberWheel.itemExtent * 3,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: NumberWheel.itemExtent,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: NumberWheel.itemExtent,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) =>
                    widget.onChanged(i % widget.count),
                childDelegate: ListWheelChildLoopingListDelegate(
                  children: [
                    for (var i = 0; i < widget.count; i++)
                      Listener(
                        onPointerSignal: _onSignal,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toValue(i),
                          child: Center(child: Text(pad2(i), style: style)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
