import 'dart:async';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/error_log.dart';

/// Logs each photo's upload as a lifecycle event: the first failure (per
/// photo, per run -- a PC that is off for hours is one line, not one every
/// 10 s) and the success. Hooked to the outbox's `onSent`.
class UploadLog {
  /// Creates the log, writing through [errors].
  new(this.errors);

  /// Where the events go.
  final ErrorLog errors;

  final _failed = <String>{};

  /// One send of [path] (`Reading/`-relative) ended with [error], or went.
  /// A sidecar stands for its photo: it goes first, so it fails first.
  void call(String path, DavException? error) {
    if (!path.startsWith('inbox/')) return;
    final file = path.substring('inbox/'.length);
    final photo = file.endsWith('.json')
        ? file.substring(0, file.length - '.json'.length)
        : file;
    if (error != null) {
      if (_failed.add(photo)) {
        unawaited(
          errors.event('upload', 'upload-failed', {
            'photo': photo,
            'error': '$error',
          }),
        );
      }
    } else if (photo == file) {
      _failed.remove(photo);
      unawaited(errors.event('upload', 'uploaded', {'photo': photo}));
    }
  }
}
