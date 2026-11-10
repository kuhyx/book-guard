import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Edit the current book: title, author, ISBN, last page and chapters.
///
/// The lookup button asks the PC to look the ISBN up everywhere and puts what
/// it found into the form for review; nothing is saved until the check
/// button.
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

  /// The PC refused the last page: its field is red until edited.
  bool _pagesBad = false;

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
      if (mounted) reportFailure(context, widget.api, 'edit_book', error);
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
      showReply(context, response);
      return;
    }
    setState(() {
      if ('${data['title'] ?? ''}'.isNotEmpty) _title.text = '${data['title']}';
      if ('${data['author'] ?? ''}'.isNotEmpty) {
        _author.text = '${data['author']}';
      }
      if (data['pages'] is int) _pages.text = '${data['pages']}';
    });
    showReply(context, response);
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
      setState(() => _pagesBad = response.code == 'bad_pages');
      showReply(context, response);
      return;
    }
    showReply(context, response);
    Navigator.of(context).pop(true);
  });

  Widget _field(
    TextEditingController c,
    IconData icon,
    String spoken, {
    bool number = false,
    bool bad = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: IconField(
      icon: icon,
      semanticLabel: spoken,
      controller: c,
      keyboardType: number ? TextInputType.number : null,
      errorBorder: bad,
      onChanged: (_) {
        if (bad) setState(() => _pagesBad = false);
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        _field(_title, Icons.title, 'Title'),
        _field(_author, Icons.person, 'Author'),
        _field(_isbn, Icons.qr_code, 'ISBN', number: true),
        Align(
          alignment: Alignment.centerLeft,
          child: GlyphButton(
            icon: Icons.travel_explore,
            semanticLabel: 'Fill from ISBN',
            onPressed: _busy ? null : _fill,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(
          _pages,
          Icons.last_page,
          'Last page of your copy',
          number: true,
          bad: _pagesBad,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (i, row) in _rows.indexed)
          Row(
            children: [
              SizedBox(
                width: 128,
                child: IconField(
                  icon: Icons.bookmark_border,
                  semanticLabel: 'Page',
                  controller: row.start,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: IconField(
                  icon: Icons.list,
                  semanticLabel: 'Chapter ${i + 1}',
                  controller: row.title,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  semanticLabel: 'Remove chapter',
                ),
                onPressed: _busy
                    ? null
                    : () => setState(() => _rows.removeAt(i).dispose()),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: GlyphButton(
            icon: Icons.playlist_add,
            semanticLabel: 'Add chapter',
            onPressed: _busy
                ? null
                : () => setState(() => _rows.add(_Row(null))),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: GlyphButton(
            icon: Icons.check,
            semanticLabel: 'Save',
            filled: true,
            onPressed: _busy ? null : _save,
          ),
        ),
      ],
    ),
  );
}
