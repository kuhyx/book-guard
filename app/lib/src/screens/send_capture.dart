import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_delivery.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:material_ui/material_ui.dart';

/// Reviews a stored photo on the app's root [navigator] and queues it with
/// its number. Needs no mounted Read tab: the review is pushed on the root
/// navigator, so a tab switch or a rebuild while the phone reads the photo
/// cannot drop it (2026-11-22: four scans in a row ended in "review-left").
/// Every step is a lifecycle event for the PC's log.
Future<void> sendCapture({
  required GuardApi api,
  required NavigatorState navigator,
  required Capture capture,
  required Uint8List bytes,
  required PageReader? reader,
  required PageContext pageContext,
  required String? isbn,
  required void Function(PhotoStatus status) show,
}) async {
  final attempt = {'attempt': capture.id};
  if (reader != null) show(PhotoStatus.reading);
  final review = await reviewPhoto(
    navigator,
    reader: reader,
    bytes: bytes,
    fileName: capture.fileName,
    pageContext: pageContext,
    errors: api.errors,
    attempt: capture.id,
  );
  if (review == null) {
    // Back, or the app went away: the photo stays on the phone.
    await api.errors.event('photo', 'review-left', attempt);
    return show(PhotoStatus.kept);
  }
  if (review.retake) {
    await api.captures.drop(capture);
    await api.errors.event('photo', 'discarded', attempt);
    return show(PhotoStatus.discarded);
  }
  // Every result but a retake carries a number; without one, keep the photo.
  final page = review.page;
  if (page == null) {
    await api.errors.event('photo', 'review-left', attempt);
    return show(PhotoStatus.kept);
  }
  await api.errors.event('photo', 'reviewed', {
    ...attempt,
    'page': page,
    'boxed': review.box != null,
  });
  final name = await api.queuePhoto(
    capture.label,
    capture.fileName,
    bytes,
    page: page,
    box: review.box,
    ocrPage: review.ocrPage,
    isbn: isbn,
  );
  await api.captures.drop(capture);
  await api.errors.event('photo', 'queued', {...attempt, 'photo': name});
  final sent = await deliverPhoto(
    api,
    name: name,
    attempt: capture.id,
    page: page,
    onSent: show,
  );
  show(sent.status);
}
