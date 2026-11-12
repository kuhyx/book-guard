import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A book as a tile: its status glyph, title and pages read.
class BookTile extends StatelessWidget {
  /// Creates the tile.
  const new(
    this.book, {
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  /// The book.
  final LibraryBook book;

  /// Opens the book.
  final VoidCallback onTap;

  /// Shows its facts.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              Icon(
                book.status == 'finished'
                    ? Icons.check_circle_outline
                    : book.current
                    ? Icons.auto_stories
                    : Icons.book_outlined,
                semanticLabel: book.status,
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: Text(
                  book.title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 4,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${book.lastPageRead ?? 0}/${book.pages ?? '?'}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A book's author, pages, dates and counts as numbers beside glyphs.
class BookFacts extends StatelessWidget {
  /// Creates the facts.
  const new(this.book, {required this.notes, super.key});

  /// The book.
  final LibraryBook book;

  /// Notes on it, the device's included.
  final int notes;

  @override
  Widget build(BuildContext context) {
    final finished = book.status == 'finished';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.author.isNotEmpty) Text(book.author),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            IconNumber(
              Icons.last_page,
              '${book.lastPageRead ?? 0}/${book.pages ?? '?'}',
              semanticLabel: 'Pages',
            ),
            if (finished)
              IconNumber(
                Icons.check_circle,
                dmy(book.finishedAt),
                semanticLabel: 'Finished',
                color: context.statusColors.success,
              )
            else if (book.status == 'reading') ...[
              IconNumber(
                Icons.today,
                dmy(book.firstReadAt),
                semanticLabel: 'First read',
              ),
              IconNumber(
                Icons.event,
                dmy(book.lastReadAt),
                semanticLabel: 'Last read',
              ),
            ],
          ],
        ),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            IconNumber(
              Icons.history,
              '${book.sessions.length}',
              semanticLabel: 'Sessions',
            ),
            IconNumber(
              Icons.sticky_note_2_outlined,
              '$notes',
              semanticLabel: 'Notes',
            ),
          ],
        ),
      ],
    );
  }
}
