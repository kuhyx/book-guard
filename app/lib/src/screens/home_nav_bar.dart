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
    destinations: [
      const NavigationDestination(icon: Icon(Icons.insights), label: 'Status'),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: readWaiting,
          child: const Icon(Icons.menu_book),
        ),
        label: 'Read',
      ),
      const NavigationDestination(
        icon: Icon(Icons.library_books),
        label: 'Book',
      ),
      const NavigationDestination(
        icon: Icon(Icons.local_library),
        label: 'Library',
      ),
    ],
  );
}
