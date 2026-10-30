/// The first character at or after [offset] that is not whitespace (the
/// text's length when only whitespace is left).
int firstVisible(String text, int offset) {
  var i = offset.clamp(0, text.length);
  while (i < text.length && text[i].trim().isEmpty) {
    i++;
  }
  return i;
}

/// [offset] moved on to the start of the next word, unless it already is
/// one: a screen never opens on half a word.
int wordAfter(String text, int offset) {
  var i = offset.clamp(0, text.length);
  if (i == 0 || text[i - 1].trim().isEmpty) return firstVisible(text, i);
  while (i < text.length && text[i].trim().isNotEmpty) {
    i++;
  }
  return firstVisible(text, i);
}
