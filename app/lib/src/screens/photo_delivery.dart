import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';

/// How a queued photo's trip to the PC ended: the status to draw (its
/// `good` is null while the photo only sits on the phone).
typedef Delivery = ({PhotoStatus status});

/// Sends the queued photo [name] (photo attempt [attempt], read as [page]
/// on the phone) and, if the PC is reachable, waits for its reading;
/// [onSent] gets the status to draw while it waits. Every step is a
/// lifecycle event; a rejection is also an error entry.
Future<Delivery> deliverPhoto(
  GuardApi api, {
  required String name,
  required String attempt,
  required int? page,
  required void Function(PhotoStatus status) onSent,
}) async {
  final ids = {'attempt': attempt, 'photo': name};
  if (await api.flush() > 0) {
    await api.errors.event('photo', 'waiting', ids);
    return (status: PhotoStatus.saved(page));
  }
  await api.errors.event('photo', 'sent', ids);
  onSent(PhotoStatus.uploaded(page));
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
  return (status: PhotoStatus.of(read));
}
