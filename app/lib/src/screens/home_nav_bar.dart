import 'package:flutter/material.dart';

/// The four tabs at the bottom of the home screen; the Read tab carries a
/// dot while a session waits for a check photo or a summary.
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
      _tab(Icons.menu_book, 'read', dot: readWaiting),
      _tab(Icons.library_books, 'book'),
      _tab(Icons.local_library, 'library'),
    ],
  );
}

/// One icon-only destination: no label and no tooltip, so nothing is
/// painted but the glyph; the name is only spoken.
NavigationDestination _tab(IconData glyph, String name, {bool dot = false}) {
  final icon = Icon(glyph, semanticLabel: name);
  return NavigationDestination(
    icon: dot ? Badge(child: icon) : icon,
    label: '',
    tooltip: '',
  );
}
