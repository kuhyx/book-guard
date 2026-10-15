/// Every book file format the PC can read, grouped by the tool that reads
/// it -- a mirror of book-guard's `_booktext.FORMAT_GROUPS`. A Python test
/// parses this file and fails on any drift, so keep one
/// `BookFormatGroup('<key>', ...)` per group with plain string literals.
library;

/// One tool's formats, for the attach modal.
class BookFormatGroup {
  /// Creates a group.
  const new(this.key, this.label, this.extensions);

  /// The PC's group name (`calibre`, `pdf`, `djvu`, `text`).
  final String key;

  /// What the modal calls it.
  final String label;

  /// Extensions without the dot.
  final List<String> extensions;
}

/// The groups, in the order the modal lists them.
const bookFormatGroups = <BookFormatGroup>[
  BookFormatGroup('calibre', 'Ebooks (calibre)', [
    'epub', 'kepub', 'mobi', 'azw', 'azw1', 'azw3', 'azw4', 'prc', 'pdb', //
    'fb2', 'fbz', 'lit', 'lrf', 'rb', 'snb', 'tcr', 'pml', 'chm', 'rtf', //
    'docx', 'odt', 'htmlz', 'txtz', 'cbz', 'cbr', 'cb7', 'cbc',
  ]),
  BookFormatGroup('pdf', 'PDF', ['pdf']),
  BookFormatGroup('djvu', 'DjVu', ['djvu', 'djv']),
  BookFormatGroup('text', 'Plain text', [
    'txt', 'md', 'text', 'html', 'htm', 'xhtml', //
  ]),
];

/// Every readable extension, flattened.
final List<String> bookExtensions = [
  for (final group in bookFormatGroups) ...group.extensions,
];

/// Whether the PC can read a file called [name], by its extension.
bool isBookFile(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 &&
      bookExtensions.contains(name.substring(dot + 1).toLowerCase());
}
