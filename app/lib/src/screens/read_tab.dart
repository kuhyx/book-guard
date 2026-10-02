import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Takes a photo: the camera on the phone, a file on the desktop. Returns
/// the original file untouched -- no size or quality options, because any
/// re-encode would strip the EXIF capture time the session clock runs on.
typedef PhotoSource = Future<XFile?> Function({required bool camera});

/// The default [PhotoSource]: the camera, or the gallery on the desktop.
Future<XFile?> pickPhoto({required bool camera}) => ImagePicker().pickImage(
  source: camera ? ImageSource.camera : ImageSource.gallery,
);

/// The reading session itself: start / stop / check photos, then the summary.
class ReadTab extends StatefulWidget {
  /// Creates the tab.
  const new({
    required this.api,
    required this.state,
    required this.desktop,
    required this.onChanged,
    super.key,
    this.photoSource = pickPhoto,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot.
  final GuardState? state;

  /// Desktop: pick photo files instead of opening a camera.
  final bool desktop;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  /// Where photos come from; replaced in tests.
  final PhotoSource photoSource;

  @override
  State<ReadTab> createState() => _ReadTabState();
}

class _ReadTabState extends State<ReadTab> {
  final _summary = TextEditingController();
  bool _busy = false;
  String? _verdict;
  String? _photoNote;
  bool? _passed;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) showError(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  /// Uploads a photo and keeps the buttons locked until the PC has read
  /// it, then says what it saw -- a photo must never just vanish.
  Future<void> _photo(String label) => _run(() async {
    final file = await widget.photoSource(camera: !widget.desktop);
    if (file == null) return;
    setState(() => _photoNote = 'Uploading...');
    final name = await widget.api.uploadPhoto(
      '${label}_${file.name}',
      await file.readAsBytes(),
    );
    if (!mounted) return;
    setState(() => _photoNote = 'Uploaded - waiting for the PC to read it...');
    final read = await widget.api.waitForPhoto(name);
    if (!mounted) return;
    final note = photoVerdict(read);
    setState(() => _photoNote = note);
    read != null && read.accepted
        ? showToast(context, note)
        : showError(context, note);
  });

  Future<void> _submit(SessionInfo session) => _run(() async {
    setState(() {
      _verdict = 'Grading - this takes up to a minute...';
      _passed = null;
    });
    final response = await widget.api.send('summary', {
      'session_id': session.id,
      'summary': _summary.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _verdict = response.message;
      _passed = response.passed;
    });
    if (response.passed ?? false) _summary.clear();
  });

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final checks = state?.needCheck ?? const [];
    final quiz = state?.needSummary ?? const [];
    final reading = state?.openStart;
    final verdict = _verdict;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        const SectionHeader('Session photos'),
        Text(
          reading == null
              ? 'Photograph the open page (number visible) when you start.'
              : 'Reading since p. $reading - photograph the page where you '
                    'stop.',
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _photo(reading == null ? 'start' : 'stop'),
              icon: Icon(
                widget.desktop ? Icons.upload_file : Icons.photo_camera,
              ),
              label: Text(reading == null ? 'Start reading' : 'Stop reading'),
            ),
            for (final s in checks)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _photo('check${s.checkPage}'),
                icon: const Icon(Icons.fact_check),
                label: Text('Photograph page ${s.checkPage}'),
              ),
          ],
        ),
        if (_photoNote case final note?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(note),
        ],
        if (quiz.isNotEmpty) ...[
          SectionHeader(
            'Summary for p. ${quiz.first.startPage}-${quiz.first.endPage}',
          ),
          const Text(
            '3-5 sentences in your own words (Polish or English) about what '
            'happened in these pages.',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _summary,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _busy ? null : () => _submit(quiz.first),
            child: const Text('Submit summary'),
          ),
        ],
        if (verdict != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            verdict,
            style: TextStyle(
              color: switch (_passed) {
                true => theme.extension<AppStatusColors>()?.success,
                false => theme.colorScheme.error,
                null => null,
              },
            ),
          ),
        ],
        if (state != null && state.photos.isNotEmpty) ...[
          const SectionHeader('Your photos'),
          PhotoGallery(api: widget.api, photos: state.photos),
        ],
      ],
    );
  }
}
