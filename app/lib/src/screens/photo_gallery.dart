import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/fit_sheet.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Superseded by `PhotoStatus.of` (a glyph, not a sentence); paints
/// nothing. Left only until `book_tab.dart` has switched.
@Deprecated('Use PhotoStatus.of and showPhotoStatus.')
String photoVerdict(PhotoInfo? photo) => '';

/// The full-size photo at [file] (relative to `Reading/`), zoomable.
void openPhoto(BuildContext context, GuardApi api, String file) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: RemoteImage(
          bytes: api.fetchBytes(file),
          fit: BoxFit.contain,
          zoom: true,
        ),
      ),
    );

/// The newest uploads as a 3-column grid fitted to its box and paged
/// sideways; tap for full size, long-press for the time and the verdict.
class PhotoGallery extends StatefulWidget {
  /// Creates the gallery.
  const new({required this.api, required this.photos, super.key});

  /// Where the images come from.
  final GuardApi api;

  /// Newest first, from the snapshot.
  final List<PhotoInfo> photos;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  /// One download per thumbnail for the life of the tab.
  final _thumbs = <String, Future<Uint8List?>>{};

  Future<Uint8List?> _thumb(String path) =>
      _thumbs.putIfAbsent(path, () => widget.api.fetchBytes(path));

  void _open(PhotoInfo photo) => openPhoto(context, widget.api, photo.file);

  void _details(PhotoInfo photo) => showFitSheet(
    context,
    Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PhotoMark(photo),
        _verdict(context, photo),
        _when(photo.takenAt),
        IconButton(
          icon: const Icon(Icons.zoom_in, semanticLabel: 'full size'),
          onPressed: () => _open(photo),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => FitGrid(
    itemCount: widget.photos.length,
    padding: EdgeInsets.zero,
    itemBuilder: (context, i) {
      final photo = widget.photos[i];
      return Card(
        key: ValueKey('photo-${photo.name}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(photo),
          onLongPress: () => _details(photo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RemoteImage(bytes: _thumb(photo.thumb), fit: BoxFit.cover),
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: _Chip(child: PhotoMark(photo)),
              ),
              Positioned(
                right: AppSpacing.xs,
                top: AppSpacing.xs,
                child: _Chip(child: _verdict(context, photo, size: 18)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The PC's verdict: a green tick, or the reject glyph.
Widget _verdict(BuildContext context, PhotoInfo photo, {double size = 24}) =>
    photo.accepted
    ? Icon(
        Icons.check_circle,
        size: size,
        color: context.statusColors.success,
        semanticLabel: 'accepted',
      )
    : RejectBadge(photo.reason, size: size);

/// A mark kept legible over any photo.
class _Chip extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(AppSpacing.xs),
    ),
    child: Padding(padding: const EdgeInsets.all(2), child: child),
  );
}

/// `15.10 16:25`; an icon when the camera wrote no time.
Widget _when(DateTime? taken) {
  if (taken == null) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Icon(Icons.history_toggle_off, semanticLabel: 'time unknown'),
    );
  }
  final t = taken.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return Text('${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}');
}

/// An image fetched from the share, with a spinner and a broken-image icon.
class RemoteImage extends StatelessWidget {
  /// Creates the image.
  const new({
    required this.bytes,
    required this.fit,
    this.zoom = false,
    super.key,
  });

  /// The download.
  final Future<Uint8List?> bytes;

  /// How it fills its box.
  final BoxFit fit;

  /// Pinch-to-zoom (the full-size view).
  final bool zoom;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: snapshot.connectionState == ConnectionState.done
              ? const Icon(Icons.broken_image_outlined)
              : const Center(child: CircularProgressIndicator()),
        );
      }
      final image = Image.memory(data, fit: fit);
      return zoom ? InteractiveViewer(child: image) : image;
    },
  );
}
