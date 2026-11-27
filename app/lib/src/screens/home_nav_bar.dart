import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/screens/step_style.dart';
import 'package:material_ui/material_ui.dart';

/// The step the Read tab owes, as its badge shows it: the red stop while
/// reading, else the amber pen while a summary is unsent, else none. The
/// phone's [local] view wins over the PC's [state], as on the Read tab.
StepKind? readStepFor(
  LocalView? local,
  GuardState? state,
  Set<String> grading,
) {
  final reading = local != null ? local.openStart : state?.openStart;
  if (reading != null) return StepKind.stop;
  final owed = local?.needSummary ?? state?.needSummary ?? const [];
  return owed.any((s) => !grading.contains(s.id)) ? StepKind.summary : null;
}

/// The four tabs at the bottom of the home screen; the Read tab carries the
/// glyph of the step it owes ([readStepFor]).
class HomeNavBar extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.selected,
    required this.onSelected,
    super.key,
    this.readStep,
  });

  /// The tab shown.
  final int selected;

  /// Switches tabs.
  final ValueChanged<int> onSelected;

  /// The step the Read tab owes; null shows no badge.
  final StepKind? readStep;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selected,
    onDestinationSelected: onSelected,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
    destinations: [
      _tab(Icons.insights, 'status'),
      _tab(Icons.menu_book, 'read', step: readStep),
      _tab(Icons.library_books, 'book'),
      _tab(Icons.local_library, 'library'),
    ],
  );
}

/// One icon-only destination: no label and no tooltip, so nothing is
/// painted but the glyph; the name is only spoken.
/// A [step] owed there badges it with that step's glyph and colour.
NavigationDestination _tab(IconData glyph, String name, {StepKind? step}) {
  final icon = Icon(glyph, semanticLabel: name);
  return NavigationDestination(
    icon: step == null ? icon : Builder(builder: (c) => _badged(c, icon, step)),
    label: '',
    tooltip: '',
  );
}

Widget _badged(BuildContext context, Widget icon, StepKind step) {
  final style = stepStyle(context, step);
  return Badge(
    backgroundColor: style.color,
    label: Icon(style.icon, size: 10, color: Colors.white),
    child: icon,
  );
}
