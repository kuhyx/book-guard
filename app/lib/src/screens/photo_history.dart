import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/journal.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The bottom of the Read tab: photos that failed (box again, report),
/// then every photo the PC filed.
class PhotoHistory extends StatelessWidget {
  /// Creates the section.
  const new({
    required this.api,
    required this.state,
    required this.journal,
    required this.onChanged,
    super.key,
    this.reader,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot (possibly the cached one).
  final GuardState? state;

  /// Every photo taken on this device.
  final List<JournalEntry> journal;

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FailedPhotos(
          api: api,
          state: state,
          journal: journal,
          reader: reader,
          onChanged: onChanged,
        ),
        if (state != null && state.photos.isNotEmpty) ...[
          const SectionHeader('Your photos'),
          PhotoGallery(api: api, photos: state.photos),
        ],
      ],
    );
  }
}
