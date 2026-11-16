import 'package:book_guard_app/src/library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/screens/library_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A book's tile fill: a fixed hue from the palette picked by a stable
/// hash of its ISBN (title if none), at one of two depths, so the same
/// book keeps its colour on every run and every device.
Color bookColor(LibraryBook book, Color surface) {
  const hues = [
    AppPalette.accent,
    AppPalette.success,
    AppPalette.warning,
    AppPalette.danger,
  ];
  // FNV-1a: String.hashCode is not promised to be stable across runs.
  var hash = 0x811c9dc5;
  for (final unit in (book.isbn.isEmpty ? book.title : book.isbn).codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  final hue = hues[hash % hues.length];
  final depth = (hash ~/ hues.length).isEven ? 0.0 : 0.45;
  return Color.lerp(hue, surface, depth)!;
}

/// A book as a colour tile: its status glyph and pages read; the title,
/// author and dates sit behind a long-press.
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

  /// Shows its title and facts.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = bookColor(book, theme.colorScheme.surface);
    // Dark glyphs on a light fill, light on a dark one (dark theme).
    final ink = fill.computeLuminance() > 0.3
        ? AppPalette.ink
        : AppPalette.textOnDark;
    return Card(
      color: fill,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Semantics(
          label: book.title,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                book.status == 'finished'
                    ? Icons.check_circle_outline
                    : book.current
                    ? Icons.auto_stories
                    : Icons.book_outlined,
                color: ink,
                size: 32,
                semanticLabel: book.status,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${book.lastPageRead ?? 0}/${book.pages ?? '?'}',
                style: theme.textTheme.labelSmall?.copyWith(color: ink),
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
