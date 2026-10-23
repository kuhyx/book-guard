import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/screens/session_times.dart' show hhmm;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The reader's bottom bar: the estimated paper page, previous / next
/// screen, and Start / Stop -- with what is running, or what starting here
/// does to an open paper start photo.
class ReaderBar extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.map,
    required this.offset,
    required this.start,
    required this.onStart,
    required this.onStop,
    super.key,
    this.paperStart,
    this.onPrevious,
    this.onNext,
  });

  /// The page map.
  final EbookMap map;

  /// Where the reader is.
  final int offset;

  /// The running in-app session, if any.
  final ReadingStart? start;

  /// The page of an open paper start photo, if any.
  final int? paperStart;

  /// The previous screen; null on the first.
  final VoidCallback? onPrevious;

  /// The next screen; null on the last.
  final VoidCallback? onNext;

  /// "Start reading here".
  final VoidCallback onStart;

  /// "Stop reading".
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final (start, paper) = (this.start, paperStart);
    final page = map.shownPage(offset);
    final last = map.lastPage;
    final status = start == null
        ? paper != null
              ? 'Reading here closes the open start photo of p. $paper: '
                    'take a new start photo when you go back to paper.'
              : null
        : 'Reading since ${hhmm(start.startedAt)} from '
              '≈ p. ${map.pageAt(start.offset)}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status != null) Text(status, textAlign: TextAlign.center),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrevious,
                ),
                Text('≈ p. $page${last == null ? '' : ' / $last'}'),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onNext,
                ),
                const Spacer(),
                if (start == null)
                  FilledButton(
                    onPressed: onStart,
                    child: const Text('Start reading here'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: onStop,
                    child: const Text('Stop reading'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
