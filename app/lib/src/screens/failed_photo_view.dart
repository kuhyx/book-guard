import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/failed_photo.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:material_ui/material_ui.dart';

/// The photo view a grid tile opens, showing [bytes] (the phone's copy of
/// [failed]); a photo the PC has not got yet can be sent again from there.
void openFailedPhoto(
  BuildContext context, {
  required FailedPhoto failed,
  required Future<Uint8List?> bytes,
  required GuardApi api,
  required Future<void> Function() onChanged,
}) => showPhotoView(
  context,
  bytes,
  actions: [
    if (failed.pc == null)
      GlyphButton(
        icon: Icons.cloud_upload_outlined,
        semanticLabel: 'Send again',
        onPressed: () => unawaited(_sendAgain(context, api, onChanged)),
      ),
  ],
);

/// Sends what the outbox holds (the photo is still in it: an upload that
/// failed is kept), then refetches so a sent photo leaves the strip.
Future<void> _sendAgain(
  BuildContext context,
  GuardApi api,
  Future<void> Function() onChanged,
) async {
  Navigator.of(context).pop();
  final waiting = await api.flush();
  if (!context.mounted) return;
  showCue(
    context,
    waiting == 0
        ? const Cue(CueKind.ok, icon: Icons.cloud_done, semanticLabel: 'sent')
        : const Cue(
            CueKind.warn,
            icon: Icons.cloud_off,
            semanticLabel: 'not sent, still on the phone',
          ),
  );
  unawaited(onChanged());
}
