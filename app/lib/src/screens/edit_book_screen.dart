import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Edit the current book: title, author, ISBN, last page and chapters.
///
/// "Fill from ISBN" asks the PC to look the ISBN up everywhere and puts what
/// it found into the form for review; nothing is saved until Save.
class EditBookScreen extends StatefulWidget {
  /// Creates the screen for [book].
  const new({required this.api, required this.book, super.key});

  /// The PC.
  final GuardApi api;

  /// The book as registered now.
  final BookInfo book;

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _Row {
  new(ChapterInfo? chapter)
    : start = TextEditingController(
        text: chapter == null ? '' : '${chapter.start}',
      ),
      title = TextEditingController(text: chapter?.title ?? '');

  final TextEditingController start;
  final TextEditingController title;

  void dispose() {
    start.dispose();
    title.dispose();
  }
}

class _EditBookScreenState extends State<EditBookScreen> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _isbn = TextEditingController(text: widget.book.isbn);
  late final _pages = TextEditingController(
    text: widget.book.pages == null ? '' : '${widget.book.pages}',
  );
  late final List<_Row> _rows = [for (final c in widget.book.chapters) _Row(c)];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _author, _isbn, _pages]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
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
    }
  }

  Future<void> _fill() => _run(() async {
    final response = await widget.api.send('lookup', {
      'isbn': _isbn.text.trim(),
    });
    if (!mounted) return;
    final data = response.data;
    if (!response.ok || data == null) {
      showError(context, response.message);
      return;
    }
    setState(() {
      if ('${data['title'] ?? ''}'.isNotEmpty) _title.text = '${data['title']}';
      if ('${data['author'] ?? ''}'.isNotEmpty) {
        _author.text = '${data['author']}';
      }
      if (data['pages'] is int) _pages.text = '${data['pages']}';
    });
    showToast(context, '${response.message} - review, then Save.');
  });

  Future<void> _save() => _run(() async {
    final response = await widget.api.send('edit_book', {
      'title': _title.text.trim(),
      'author': _author.text.trim(),
      'isbn': _isbn.text.trim(),
      'pages': _pages.text.trim(),
      'chapters': [
        for (final r in _rows)
          if (int.tryParse(r.start.text.trim()) case final start?)
            if (r.title.text.trim().isNotEmpty)
              {'start': start, 'title': r.title.text.trim()},
      ],
    });
    if (!mounted) return;
    if (!response.ok) {
      showError(context, response.message);
      return;
    }
    showToast(context, response.message);
    Navigator.of(context).pop(true);
  });

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit book')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        _field(_title, 'Title'),
        _field(_author, 'Author'),
        _field(_isbn, 'ISBN', number: true),
        OutlinedButton.icon(
          onPressed: _busy ? null : _fill,
          icon: const Icon(Icons.travel_explore),
          label: const Text('Fill from ISBN'),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_pages, 'Last page of your copy', number: true),
        const SectionHeader('Chapters'),
        for (final (i, row) in _rows.indexed)
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: row.start,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Page'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: row.title,
                  decoration: InputDecoration(labelText: 'Chapter ${i + 1}'),
                ),
              ),
              IconButton(
                tooltip: 'Remove chapter',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy
                    ? null
                    : () => setState(() => _rows.removeAt(i).dispose()),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _rows.add(_Row(null))),
          icon: const Icon(Icons.add),
          label: const Text('Add chapter'),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
