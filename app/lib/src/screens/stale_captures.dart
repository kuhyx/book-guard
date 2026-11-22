import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_mark.dart';
import 'package:book_guard_app/src/screens/type_page_dialog.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Stored photos [freshFor] or older: never a start or stop any more (a
/// start of 2026-10-27 would open a 26-day session). Each is read in the
/// background; keeping it sends it as a `kept_` page photo -- the keypad
/// opens holding the number read, one tap -- which the PC files off every
/// session. Or it is deleted.
class StaleCaptures extends StatefulWidget {
  /// Creates the strip.
  const new({
    required this.api,
    required this.onChanged,
    super.key,
    this.reader,
    this.clock = DateTime.now,
  });

  /// The PC (and the device's store).
  final GuardApi api;

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// Now; replaced in tests.
  final DateTime Function() clock;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  @override
  State<StaleCaptures> createState() => _StaleCapturesState();
}

class _StaleCapturesState extends State<StaleCaptures> {
  List<(Capture, Uint8List)> _stale = const [];
  final _read = <String, int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = widget.api;
    final found = <(Capture, Uint8List)>[];
    for (final c in staleCaptures(
      await api.captures.pending(),
      widget.clock(),
    )) {
      final bytes = await api.captures.bytes(c);
      if (bytes != null) found.add((c, bytes));
    }
    if (!mounted) return;
    setState(() => _stale = found);
    for (final (c, bytes) in found) {
      final page = (await widget.reader?.scan(bytes))?.hits.firstOrNull?.value;
      if (page != null && mounted) setState(() => _read[c.id] = page);
    }
  }

  Future<void> _keep(Capture c, Uint8List bytes) async {
    final read = _read[c.id];
    final page = await showDialog<int>(
      context: context,
      builder: (_) => TypePageDialog(initial: read),
    );
    if (page == null) return;
    final api = widget.api;
    final name = await api.queuePhoto(
      'kept',
      c.fileName,
      bytes,
      page: page,
      ocrPage: read,
    );
    await api.captures.drop(c);
    await api.errors.event('photo', 'kept', {'attempt': c.id, 'photo': name});
    await _drop(c);
  }

  Future<void> _delete(Capture c) async {
    await widget.api.captures.drop(c);
    await widget.api.errors.event('photo', 'discarded', {'attempt': c.id});
    await _drop(c);
  }

  Future<void> _drop(Capture c) async {
    if (mounted) {
      setState(
        () => _stale = [
          for (final s in _stale)
            if (s.$1.id != c.id) s,
        ],
      );
    }
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final (c, bytes) in _stale) _card(c, bytes)],
  );

  Widget _card(Capture c, Uint8List bytes) {
    final at = c.takenAt.toLocal();
    final read = _read[c.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 96,
              child: Image.memory(bytes, cacheWidth: 192, fit: BoxFit.cover),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  LabelMark(c.label),
                  Text('${at.day}.${at.month}'),
                  if (read != null) Text('$read'),
                ],
              ),
            ),
            GlyphButton(
              icon: Icons.bookmark_add,
              semanticLabel: 'Keep as a page photo',
              filled: true,
              onPressed: () => unawaited(_keep(c, bytes)),
            ),
            const SizedBox(width: AppSpacing.sm),
            GlyphButton(
              icon: Icons.delete_outline,
              semanticLabel: 'Delete the stored photo',
              onPressed: () => unawaited(_delete(c)),
            ),
          ],
        ),
      ),
    );
  }
}
