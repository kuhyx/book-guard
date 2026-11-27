import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/screens/step_style.dart';
import 'package:material_ui/material_ui.dart';

/// The four tabs at the bottom of the home screen; the Read tab carries the
/// summary step's amber pen while a session waits for its summary.
class HomeNavBar extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.selected,
    required this.onSelected,
    required this.readWaiting,
    super.key,
  });

  /// The tab shown.
  final int selected;

  /// Switches tabs.
  final ValueChanged<int> onSelected;

  /// Whether a session waits on the Read tab.
  final bool readWaiting;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selected,
    onDestinationSelected: onSelected,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
    destinations: [
      _tab(Icons.insights, 'status'),
      _tab(
        Icons.menu_book,
        'read',
        step: readWaiting ? StepKind.summary : null,
      ),
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
