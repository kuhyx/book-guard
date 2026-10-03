import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/self_test_none.dart'
    if (dart.library.io) 'package:book_guard_app/src/self_test_io.dart'
    as platform;

/// Runs the on-device page-reader check when adb asked for one (see
/// `self_test_io.dart`); a no-op everywhere else.
Future<void> runSelfTestIfAsked(PageReader? reader) =>
    platform.runSelfTestIfAsked(reader);
