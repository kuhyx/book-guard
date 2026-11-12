import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A sheet that scrolls on its own: the place for whatever a fitted tab
/// leaves out.
Future<void> showFitSheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: child,
      ),
    );
