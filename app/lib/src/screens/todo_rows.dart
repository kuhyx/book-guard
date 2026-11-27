/// The PC's to-do lines, shown as glyphs and the page numbers in them: the
/// lines are sentences the PC wrote, so only their numbers are painted and
/// the sentence is only the spoken label.
library;

import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/screens/icon_num.dart';
import 'package:book_guard_app/src/screens/step_style.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

final _number = RegExp(r'\d+(?:-\d+)?');
final _clock = RegExp(r'\d{1,2}:\d{2}');

/// Whether [line] asks for a summary of a range (`63-80`) in [ranges].
bool asksSummaryOf(String line, Set<String> ranges) {
  if (ranges.isEmpty || !line.toLowerCase().contains('summary')) return false;
  return TodoItem.parse(line).numbers.any(ranges.contains);
}

/// One to-do line, reduced to what can be drawn.
class TodoItem {
  /// Creates an item.
  const new(this.icon, this.numbers, {this.extra, this.clock, this.step});

  /// Reads [line]: the glyph from its key words, the numbers from its text.
  factory parse(String line) {
    final lower = line.toLowerCase();
    final numbers = [for (final m in _number.allMatches(line)) m[0]!];
    final clock = _clock.firstMatch(line)?[0];
    if (lower.startsWith('reading since')) {
      // `Reading since p. 42 (Thu 10:00)`: the page, then the time.
      // The Read tab's stop button: one glyph and colour per step.
      return TodoItem(
        Icons.stop,
        numbers.take(1).toList(),
        extra: Icons.photo_camera,
        clock: clock,
        step: StepKind.stop,
      );
    }
    if (lower.contains('no book')) {
      return const TodoItem(Icons.search, [], extra: Icons.book_outlined);
    }
    if (lower.contains('rewrite')) {
      return TodoItem(Icons.replay, numbers, extra: Icons.edit);
    }
    if (lower.contains('summary')) {
      return TodoItem(Icons.edit, numbers, step: StepKind.summary);
    }
    if (lower.contains('photo')) {
      return TodoItem(Icons.photo_camera, numbers);
    }
    return TodoItem(Icons.arrow_right, numbers);
  }

  /// The main glyph.
  final IconData icon;

  /// Page numbers and ranges, in the order the line gives them.
  final List<String> numbers;

  /// A second glyph that completes the first (what to photograph).
  final IconData? extra;

  /// A time of day, `10:00`.
  final String? clock;

  /// The Read tab step it stands for; its colour then is that step's.
  final StepKind? step;

  /// The glyph's colour: the step's, else the warning amber.
  Color color(BuildContext context) => switch (step) {
    final StepKind kind => stepStyle(context, kind).color,
    null => context.statusColors.warning,
  };
}

/// A to-do row: glyphs and numbers, the line itself only spoken.
class TodoRow extends StatelessWidget {
  /// Creates the row for [line].
  const new(this.line, {super.key});

  /// What the PC wrote.
  final String line;

  @override
  Widget build(BuildContext context) {
    final item = TodoItem.parse(line);
    return Semantics(
      label: line,
      child: ExcludeSemantics(
        child: ListTile(
          leading: Icon(item.icon, color: item.color(context)),
          title: Wrap(
            spacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.extra case final extra?) Icon(extra, size: 20),
              for (final n in item.numbers) IconNum(pagesGlyph, n),
              if (item.clock case final clock?) IconNum(minutesGlyph, clock),
            ],
          ),
        ),
      ),
    );
  }
}
