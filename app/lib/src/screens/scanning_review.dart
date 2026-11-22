import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_review.dart';
import 'package:book_guard_app/src/screens/review_buttons.dart';
import 'package:material_ui/material_ui.dart';

/// The review, open the moment the photo exists: the photo and the keypad
/// at once, the boxed number ([PhotoReview]) when the [scan] lands. No
/// screen waits on the reader (2026-11-22: a 15 s scan behind a spinner).
class ScanningReview extends StatelessWidget {
  /// Creates the screen for [bytes] while [scan] reads them.
  const new({
    required this.bytes,
    required this.scan,
    required this.reader,
    required this.context,
    super.key,
  });

  /// The photo as stored.
  final Uint8List bytes;

  /// What the phone reads off it; null when it read nothing.
  final Future<PageScan?> scan;

  /// Reads a drawn box once the scan is in.
  final PageReader reader;

  /// What the photo was taken for.
  final PageContext context;

  @override
  Widget build(BuildContext context) => FutureBuilder<PageScan?>(
    future: scan,
    builder: (context, snap) {
      final found = snap.data;
      if (found != null) {
        return PhotoReview(
          bytes: bytes,
          scan: found,
          reader: reader,
          context: this.context,
        );
      }
      return _Waiting(
        bytes: bytes,
        reading: snap.connectionState != ConnectionState.done,
      );
    },
  );
}

class _Waiting extends StatefulWidget {
  const new({required this.bytes, required this.reading});

  final Uint8List bytes;

  /// The scan is still running (else it read nothing: the keypad it is).
  final bool reading;

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _askIfUnread();
  }

  @override
  void didUpdateWidget(_Waiting old) {
    super.didUpdateWidget(old);
    _askIfUnread();
  }

  /// Nothing read: the keypad opens by itself, once.
  void _askIfUnread() {
    if (widget.reading || _asked) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_type(context));
    });
  }

  Future<void> _type(BuildContext context) async {
    // The route, not this widget: the scan may land while the keypad is up.
    final route = Navigator.of(context);
    final result = await typeReview(
      context,
      hit: null,
      pencil: null,
      ocr: null,
    );
    if (result != null) route.pop(result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, semanticLabel: 'Back'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.reading) const LinearProgressIndicator(),
          Expanded(
            child: Image.memory(
              widget.bytes,
              cacheWidth: 1080,
              fit: BoxFit.contain,
            ),
          ),
          ReviewButtons(
            hit: null,
            reading: false,
            onType: () => unawaited(_type(context)),
            onSend: () {},
          ),
        ],
      ),
    ),
  );
}
