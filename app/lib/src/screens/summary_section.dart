import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Characters from which a summary can be credited without the grader.
const summaryTarget = 150;

/// The session's page range as numerals: `12-30`, `≈ 12-30` when estimated.
String pageRange(SessionInfo session) =>
    '${session.estimated ? '≈ ' : ''}${session.startPage}-${session.endPage}';

/// The summary box for [session]: a pencil-led field, a bar that fills to
/// [summaryTarget] characters (a tick once it does) and the send button
/// carrying the page range.
class SummarySection extends StatelessWidget {
  /// Creates the section.
  const new({
    required this.session,
    required this.controller,
    required this.onSubmit,
    super.key,
    this.grader,
    this.times,
    this.enabled = true,
    this.bonus = false,
  });

  /// False while the grader has it: the text is locked.
  final bool enabled;

  /// When it was read, with the way to correct the times.
  final Widget? times;

  /// The session to summarise.
  final SessionInfo session;

  /// The summary text.
  final TextEditingController controller;

  /// Sends it; null while busy.
  final VoidCallback? onSubmit;

  /// Why grading may wait, if it may.
  final GraderNote? grader;

  /// Whether passing also earns the gaming bonus.
  final bool bonus;

  @override
  Widget build(BuildContext context) {
    final grader = this.grader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?times,
        if (grader != null) ...[
          const SizedBox(height: AppSpacing.sm),
          GraderNoteChip(grader),
        ],
        const SizedBox(height: AppSpacing.sm),
        IconField(
          icon: Icons.edit,
          semanticLabel: 'Summary',
          controller: controller,
          enabled: enabled,
          minLines: 5,
          maxLines: 10,
        ),
        const SizedBox(height: AppSpacing.sm),
        LengthBar(controller),
        const SizedBox(height: AppSpacing.sm),
        GlyphButton(
          icon: Icons.check,
          semanticLabel: 'Submit summary',
          filled: true,
          onPressed: onSubmit,
          badge: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pageRange(session)),
              if (bonus) const Icon(Icons.bolt, semanticLabel: 'gaming bonus'),
            ],
          ),
        ),
      ],
    );
  }
}

/// A bar filling to [summaryTarget] characters of [controller]'s text, with
/// a green tick once it is full.
class LengthBar extends StatelessWidget {
  /// Creates the bar.
  const new(this.controller, {super.key});

  /// The text measured.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final length = value.text.trim().length;
      final full = length >= summaryTarget;
      return Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: full ? 1 : length / summaryTarget,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'length',
            ),
          ),
          if (full) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.check_circle,
              color: context.statusColors.success,
              semanticLabel: 'long enough',
            ),
          ],
        ],
      );
    },
  );
}
