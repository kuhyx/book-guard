import 'package:book_guard_app/src/page_number.dart';

/// What the review screen settled on for one photo.
class ReviewResult {
  /// Creates a result.
  const new({this.page, this.box, this.retake = false, this.ocrPage});

  /// "Retake": the photo is deliberately thrown away. (Leaving the screen
  /// any other way returns null and keeps it.)
  final bool retake;

  /// The page number to send: read by the phone or typed on the keypad.
  /// Null only for a retake.
  final int? page;

  /// Where it is, in the stored file's pixels -- only when [page] is the
  /// number printed there.
  final Box? box;

  /// The first number OCR offered on the review screen (null: none), kept
  /// beside [page] so the PC can see where the phone was corrected.
  final int? ocrPage;
}
