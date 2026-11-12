import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The current book's author, last page, file and chapter, as glyphs and
/// numbers.
class BookDescription extends StatelessWidget {
  /// Creates the description of [book].
  const new(this.book, {super.key});

  /// The book as registered.
  final BookInfo book;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final dim = Theme.of(context).colorScheme.outline;
    final chapter = book.chapter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.author.isNotEmpty) Text(book.author),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            IconNumber(
              Icons.last_page,
              book.pages == null ? '?' : '${book.pages}',
              semanticLabel: book.pages == null
                  ? 'Last page not set'
                  : 'Last page',
              color: book.pages == null ? colors.warning : null,
            ),
            Icon(
              book.hasFile ? Icons.file_present : Icons.attach_file,
              size: 18,
              color: book.hasFile ? colors.success : dim,
              semanticLabel: book.hasFile ? 'Ebook attached' : 'No ebook file',
            ),
            if (chapter != null)
              IconNumber(
                Icons.bookmark,
                '${chapter.number}/${chapter.of}',
                semanticLabel: 'Chapter',
              )
            else if (book.chapters.isNotEmpty)
              IconNumber(
                Icons.list,
                '${book.chapters.length}',
                semanticLabel: 'Chapters',
              ),
          ],
        ),
        if (chapter != null && chapter.title.isNotEmpty) Text(chapter.title),
      ],
    );
  }
}
