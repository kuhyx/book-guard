import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/error_log.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

/// Takes a photo: the camera on the phone, a file on the desktop. Returns
/// the original file untouched -- no size or quality options, because any
/// re-encode would strip the EXIF capture time the session clock runs on.
typedef PhotoSource = Future<XFile?> Function({required bool camera});

final _epoch = DateTime.utc(1970);

/// The default [PhotoSource]: the camera, or the gallery on the desktop.
Future<XFile?> pickPhoto({required bool camera}) => ImagePicker().pickImage(
  source: camera ? ImageSource.camera : ImageSource.gallery,
);

/// The default `LostPhoto`: what Android kept from a camera the app was
/// stopped behind (`retrieveLostData`), on the phone only.
Future<(String, Uint8List)?> retrieveLostPhoto() async {
  final lost = await ImagePicker().retrieveLostData();
  final file = lost.file;
  if (lost.isEmpty || file == null) return null;
  return (file.name, await file.readAsBytes());
}

/// What the page number of a [label] photo has to fit, from the snapshot,
/// this phone's [journal] and the page reading started at.
PageContext pageContextFor(
  String label,
  GuardState? state,
  List<JournalEntry> journal,
  int? openStart,
) {
  final lastPage = state?.book?.pages;
  if (label.startsWith('check')) {
    return PageContext(
      expected: int.tryParse(label.substring(5)),
      lastPage: lastPage,
    );
  }
  if (label == 'stop') return PageContext(after: openStart, lastPage: lastPage);
  return PageContext(near: _lastEnd(state, journal), lastPage: lastPage);
}

/// Where the last session of the current book ended, for a start photo --
/// never another book's (`context_for` filters ends by isbn on the PC).
///
/// With a book known: a stop of it the PC has not read yet, else the PC's
/// own `latest_page` for it, else its newest read stop. The snapshot's
/// sessions carry no book, so they count only when none is known.
int? _lastEnd(GuardState? state, List<JournalEntry> journal) {
  final book = state?.book;
  if (book == null) {
    final ends = [
      for (final e in journal)
        if (e.label == 'stop' && e.page != null) e.page!,
    ];
    final sessions = [
      ...?state?.sessions,
    ]..sort((a, b) => (a.startedAt ?? _epoch).compareTo(b.startedAt ?? _epoch));
    return ends.isNotEmpty
        ? ends.last
        : sessions.isEmpty
        ? null
        : sessions.last.endPage;
  }
  final stops = [
    for (final e in journal)
      if (e.label == 'stop' && e.page != null && e.isbn == book.isbn) e,
  ];
  final unread = stops.where((e) => !e.seen);
  if (unread.isNotEmpty) return unread.last.page;
  return book.latestPage ?? (stops.isEmpty ? null : stops.last.page);
}

/// Reads the photo on the device and lets the reader confirm or box the
/// number. Null if they chose to retake it; an empty result when there is
/// no reader (desktop) or the image could not be read (logged).
Future<ReviewResult?> reviewPhoto(
  BuildContext context, {
  required PageReader? reader,
  required Uint8List bytes,
  required String fileName,
  required PageContext pageContext,
  required ErrorLog errors,
  String? attempt,
}) async {
  if (reader == null) return const ReviewResult();
  final scan = await reader.scan(bytes, context: pageContext);
  // What the phone read, before anyone confirms it: the step a photo was
  // once lost after (2026-10-23, "Page 252?" and then gone).
  await errors.event('photo', 'scanned', {
    'attempt': ?attempt,
    'hits': scan == null ? null : [for (final h in scan.hits) h.value],
    'turn': ?scan?.turn, // which way up it read the page (a 9 vs a 6)
  });
  if (scan == null) {
    unawaited(errors.log('reader', 'unreadable image', {'photo': fileName}));
    return const ReviewResult();
  }
  if (!context.mounted) return null;
  final result = await Navigator.of(context).push<ReviewResult>(
    MaterialPageRoute(
      builder: (_) => PhotoReview(
        bytes: bytes,
        scan: scan,
        reader: reader,
        context: pageContext,
      ),
    ),
  );
  // A photo sent with no number keeps the pencilled one the reader saw, as a
  // suggestion for the keypad only.
  if (result == null || result.retake || result.page != null) return result;
  return ReviewResult(box: result.box, pencilPage: scan.pencilPage);
}

/// How many photos taken here the PC has not read yet: an outbox glyph and
/// the count, nothing when none waits.
class SessionPrompt extends StatelessWidget {
  /// Creates the prompt.
  const new({required this.waiting, super.key});

  /// Photos taken here that the PC has not read yet.
  final int waiting;

  @override
  Widget build(BuildContext context) {
    if (waiting <= 0) return const SizedBox.shrink();
    return SpokenLabel(
      semanticLabel: 'photos waiting for the PC',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(child: Icon(Icons.outbox)),
          const SizedBox(width: AppSpacing.xs),
          Text('$waiting'),
        ],
      ),
    );
  }
}
