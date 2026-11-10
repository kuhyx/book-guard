import 'dart:async';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The in-app reader's settings: the text size (a number), with a line of
/// the book's own glyphs to judge it by. The reader itself shows nothing
/// but text, so this is where the size is chosen; it reads it on opening.
class ReadingSettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({required this.api, super.key});

  /// Where the size is kept.
  final GuardApi api;

  /// The preview line, for tests.
  static const Key previewKey = ValueKey('reading-preview');

  @override
  State<ReadingSettingsScreen> createState() => _ReadingSettingsScreenState();
}

class _ReadingSettingsScreenState extends State<ReadingSettingsScreen> {
  double? _size;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final saved = await widget.api.savedFontSize();
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    setState(() => _size = ReadingStyle.sizeFor(saved, width));
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return Scaffold(
      appBar: AppBar(),
      body: size == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    const Icon(Icons.text_fields, semanticLabel: 'Text size'),
                    const SizedBox(width: AppSpacing.sm),
                    Text('${size.round()}'),
                  ],
                ),
                Slider(
                  value: size,
                  min: ReadingStyle.minFont,
                  max: ReadingStyle.maxFont,
                  divisions: (ReadingStyle.maxFont - ReadingStyle.minFont)
                      .round(),
                  label: '${size.round()}',
                  onChanged: (value) => setState(() => _size = value),
                  onChangeEnd: (value) =>
                      unawaited(widget.api.saveFontSize(value)),
                ),
                const SizedBox(height: AppSpacing.md),
                ColoredBox(
                  color: ReadingStyle.paper,
                  child: Padding(
                    padding: const EdgeInsets.all(ReadingStyle.sideMargin),
                    child: Text(
                      // Digits and single letters, the accented ones too:
                      // the glyphs to judge a size by, no words.
                      '0123456789 A a Ą ą Ć ć Ę ę Ł ł Ń ń Ó ó Ś ś Ź ź Ż ż',
                      key: ReadingSettingsScreen.previewKey,
                      style: ReadingStyle.text(size),
                      textScaler: ReadingStyle.scaler,
                      textHeightBehavior: ReadingStyle.heightBehavior,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
