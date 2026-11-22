import 'package:book_guard_app/src/capture_stage.dart';
import 'package:book_guard_app/src/page_reader.dart';

/// The web build has no device folder to be driven through.
Future<void> runSelfTestIfAsked(PageReader? reader) async {}

/// Nothing is staged on the web build.
Future<List<StagedCapture>> takeStagedCaptures() async => const [];
