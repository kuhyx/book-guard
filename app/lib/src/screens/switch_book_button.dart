import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/iso_offset.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/ui/hold_button.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The read-now button for [book]: queues a `switch_book` request (after a
/// hold-to-confirm when a session is open) and hides itself once queued or
/// when the book is already the current one.
class SwitchBookButton extends StatefulWidget {
  /// Creates the button for [book].
  const new({
    required this.api,
    required this.book,
    this.state,
    this.onSwitched,
    super.key,
  });

  /// Where the request is queued.
  final GuardApi api;

  /// The book to switch to.
  final LibraryBook book;

  /// The live snapshot: tells whether a session is open.
  final GuardState? state;

  /// Called with the ISBN once the switch is queued.
  final ValueChanged<String>? onSwitched;

  @override
  State<SwitchBookButton> createState() => _SwitchBookButtonState();
}

class _SwitchBookButtonState extends State<SwitchBookButton> {
  /// Whether the switch was queued from this button.
  bool _switched = false;

  /// Whether a paper session (start photo, no stop yet) or an in-app one
  /// is running.
  Future<bool> _sessionOpen() async {
    final state = widget.state;
    final journal = await widget.api.journal.load();
    final paper = localView(state, journal)?.openStart ?? state?.openStart;
    if (paper != null) return true;
    final library = await widget.api.cachedLibrary();
    final isbns = {
      ?state?.book?.isbn,
      for (final b in library?.books ?? const <LibraryBook>[])
        if (b.current) b.isbn,
    };
    for (final isbn in isbns) {
      if (await widget.api.readingStart(isbn) != null) return true;
    }
    return false;
  }

  Future<void> _readNow() async {
    if (await _sessionOpen()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Icon(
            Icons.warning_amber,
            size: 48,
            color: context.statusColors.warning,
            semanticLabel: 'A session is open: take its stop photo first',
          ),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
            ),
            // The switch happens only once the ring is full.
            HoldButton(
              icon: Icons.auto_stories,
              semanticLabel: 'Switch anyway',
              onConfirmed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    final book = widget.book;
    final response = await widget.api.sendQueued('switch_book', {
      'isbn': book.isbn,
      'at': isoWithOffset(DateTime.now()),
    });
    if (!mounted) return;
    if (!response.ok) {
      showReply(context, response);
      return;
    }
    setState(() => _switched = true);
    widget.onSwitched?.call(book.isbn);
    showReply(context, response);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book.current || _switched) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: GlyphButton(
        icon: Icons.auto_stories,
        semanticLabel: 'Read this now',
        filled: true,
        onPressed: _readNow,
      ),
    );
  }
}
