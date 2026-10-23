import 'package:book_guard_app/src/page_number.dart';

/// What the review screen settled on for one photo.
class ReviewResult {
  /// Creates a result.
  const new({this.page, this.box, this.retake = false});

  /// "Retake": the photo is deliberately thrown away. (Leaving the screen
  /// any other way returns null and keeps it.)
  final bool retake;

  /// The page number the phone read (null: let the PC decide).
  final int? page;

  /// Where it is, in the stored file's pixels.
  final Box? box;
}
