import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// What to tell the reader once the PC has (or has not) read a photo.
String photoVerdict(PhotoInfo? photo) {
  if (photo == null) {
    return 'The PC has not read it yet - it will when it is on.';
  }
  if (!photo.accepted) {
    return 'Not accepted: ${photo.caption}. Retake it with the page number '
        'in view.';
  }
  return switch (photo.kind) {
    'page' => 'Read as page ${photo.page}.',
    'toc' => 'Contents read.',
    _ => 'Barcode read.',
  };
}

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

/// The newest uploads with what the PC made of each; tap for full size.
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

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final photo in widget.photos)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox.square(
            dimension: 56,
            child: RemoteImage(bytes: _thumb(photo.thumb), fit: BoxFit.cover),
          ),
          title: Text(photo.caption),
          subtitle: Text(_when(photo.takenAt)),
          trailing: Icon(
            photo.accepted ? Icons.check_circle : Icons.error_outline,
          ),
          onTap: () => _open(photo),
        ),
    ],
  );
}

String _when(DateTime? taken) {
  if (taken == null) return 'time unknown';
  final t = taken.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
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
