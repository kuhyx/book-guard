/// An icon-captioned text field and a spoken-only name for any widget.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A text field captioned by a leading icon; the old label words live only
/// in [semanticLabel] (screen readers, tests), never painted. The value the
/// reader types stays visible: it is content.
class IconField extends StatelessWidget {
  /// Creates a field captioned by [icon].
  const new({
    required this.icon,
    required this.semanticLabel,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.textInputAction,
    this.autofocus = false,
    this.autocorrect = true,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.errorBorder = false,
    this.fieldKey,
    super.key,
  });

  /// Painted caption.
  final IconData icon;

  /// Spoken caption; never painted.
  final String semanticLabel;

  /// Backing controller.
  final TextEditingController? controller;

  /// Focus handle, e.g. to jump here after an unknown ISBN.
  final FocusNode? focusNode;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Hides the typed characters.
  final bool obscure;

  /// Trailing widget, e.g. a visibility toggle.
  final Widget? suffix;

  /// Change callback.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Input formatters, e.g. digits only.
  final List<TextInputFormatter>? inputFormatters;

  /// The keyboard's action button.
  final TextInputAction? textInputAction;

  /// Whether the field grabs focus when it first appears.
  final bool autofocus;

  /// Whether the keyboard may autocorrect (false for secrets).
  final bool autocorrect;

  /// Lines shown at least; null = one.
  final int? minLines;

  /// Lines shown at most; null = grows without limit.
  final int? maxLines;

  /// The most characters it takes (the counter shows numbers only).
  final int? maxLength;

  /// Whether it can be edited.
  final bool enabled;

  /// Draws the border in the error colour (an empty required field).
  final bool errorBorder;

  /// Key given to the inner [TextField].
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final border = errorBorder
        ? OutlineInputBorder(borderSide: BorderSide(color: error, width: 2))
        : null;
    // MergeSemantics folds the spoken label into the TextField's own node;
    // a bare Semantics(textField: true) wrapper makes a dead duplicate box.
    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        child: TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          autofocus: autofocus,
          autocorrect: autocorrect,
          enableSuggestions: autocorrect,
          minLines: minLines,
          maxLines: obscure ? 1 : maxLines,
          maxLength: maxLength,
          enabled: enabled,
          decoration: InputDecoration(
            prefixIcon: ExcludeSemantics(
              child: Icon(icon, color: errorBorder ? error : null),
            ),
            suffixIcon: suffix,
            enabledBorder: border,
            focusedBorder: border,
          ),
        ),
      ),
    );
  }
}

/// Gives [child] a spoken name without painting any text.
class SpokenLabel extends StatelessWidget {
  /// Creates a named wrapper around [child].
  const new({required this.semanticLabel, required this.child, super.key});

  /// Spoken name; never painted.
  final String semanticLabel;

  /// The widget being named.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(label: semanticLabel, container: true, child: child);
}

/// An icon-only button, at least 48 dp, whose old wording is spoken only.
class GlyphButton extends StatelessWidget {
  /// Creates the button; [filled] makes it the screen's main action.
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.filled = false,
    this.badge,
    this.color,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// Spoken name; never painted (no tooltip: a long-press would show it).
  final String semanticLabel;

  /// Tap action; null disables it.
  final VoidCallback? onPressed;

  /// The screen's main action: filled in the accent colour.
  final bool filled;

  /// Content beside the glyph (a page number), shown as is.
  final Widget? badge;

  /// Tint for the glyph; the theme's when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, semanticLabel: semanticLabel, color: color);
    final extra = badge;
    final child = extra == null
        ? glyph
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [glyph, const SizedBox(width: 8), extra],
          );
    const size = Size(64, 48);
    return filled
        ? FilledButton(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: onPressed,
            child: child,
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: onPressed,
            child: child,
          );
  }
}
