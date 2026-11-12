import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One catalogue hit: title, author, pages and ISBN; a tap registers it
/// (or names its ISBN when no catalogue knew the book).
class BookHitTile extends StatelessWidget {
  /// Creates the tile for [hit].
  const new({
    required this.hit,
    required this.registering,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  /// The catalogue's answer.
  final BookHit hit;

  /// Whether a tap registers the book (false: it names an unknown ISBN).
  final bool registering;

  /// Whether the tile takes a tap.
  final bool enabled;

  /// Registers the hit.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(hit.title),
    subtitle: Wrap(
      spacing: AppSpacing.md,
      children: [
        if (hit.author.isNotEmpty) Text(hit.author),
        IconNumber(
          Icons.last_page,
          hit.pages == null ? '?' : '${hit.pages}',
          semanticLabel: 'Pages',
        ),
        if (hit.isbn case final isbn?)
          IconNumber(Icons.qr_code, isbn, semanticLabel: 'ISBN'),
      ],
    ),
    trailing: Icon(
      registering ? Icons.add : Icons.link,
      semanticLabel: registering ? 'Register' : 'Name the ISBN',
    ),
    enabled: enabled,
    onTap: onTap,
  );
}

/// The search found nothing: the ISBN field below is the way on.
class NoBooksFound extends StatelessWidget {
  /// Creates the notice.
  const new({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Center(
      child: Icon(
        Icons.search_off,
        size: 64,
        color: context.statusColors.warning,
        semanticLabel: 'No books found: enter the ISBN below',
      ),
    ),
  );
}
