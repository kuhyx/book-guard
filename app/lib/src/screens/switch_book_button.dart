import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/iso_offset.dart';
import 'package:book_guard_app/src/library_store.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// "Read this now" for [book]: queues a `switch_book` request (after a
/// confirmation when a session is open) and hides itself once queued or when
/// the book is already the current one.
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

  /// Called with the ISBN once "Read this now" is queued.
  final ValueChanged<String>? onSwitched;

  @override
  State<SwitchBookButton> createState() => _SwitchBookButtonState();
}

class _SwitchBookButtonState extends State<SwitchBookButton> {
  /// Whether "Read this now" was queued from this button.
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
          content: const Text(
            'A session is open: take its stop photo first. Switch anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Switch anyway'),
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
    }, 'Switch to ${book.title}');
    if (!mounted) return;
    if (!response.ok) {
      showError(context, response.message);
      return;
    }
    setState(() => _switched = true);
    widget.onSwitched?.call(book.isbn);
    showToast(context, response.message);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book.current || _switched) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _readNow,
        icon: const Icon(Icons.auto_stories),
        label: const Text('Read this now'),
      ),
    );
  }
}
