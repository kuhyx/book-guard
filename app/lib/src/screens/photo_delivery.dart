import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';

/// How a queued photo's trip to the PC ended: the line to show, and
/// whether it is good news (null: saved on the phone, nothing to pop up).
typedef Delivery = ({String note, bool? good});

/// Sends the queued photo [name] (photo attempt [attempt], read as [page]
/// on the phone) and, if the PC is reachable, waits for its reading;
/// [onSent] gets the line to show while it waits. Every step is a
/// lifecycle event; a rejection is also an error entry.
Future<Delivery> deliverPhoto(
  GuardApi api, {
  required String name,
  required String attempt,
  required int? page,
  required void Function(String note) onSent,
}) async {
  final ids = {'attempt': attempt, 'photo': name};
  final seen = page == null ? '' : ' (p. $page)';
  if (await api.flush() > 0) {
    await api.errors.event('photo', 'waiting', ids);
    return (
      note:
          'Saved on the phone$seen - it goes to the PC as soon as the PC is '
          'reachable.',
      good: null,
    );
  }
  await api.errors.event('photo', 'sent', ids);
  onSent('Uploaded$seen - waiting for the PC...');
  final read = await api.waitForPhoto(name);
  await api.errors.event('photo', read == null ? 'pc-not-yet' : 'pc-read', {
    ...ids,
    if (read != null) ...{'accepted': read.accepted, 'pc_page': read.page},
  });
  if (read != null && !read.accepted) {
    unawaited(
      api.errors.log('photo', read.reason, {'photo': name, 'phone_page': page}),
    );
  }
  return (note: photoVerdict(read), good: read != null && read.accepted);
}
