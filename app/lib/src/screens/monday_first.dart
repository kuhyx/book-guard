import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The app's (English) Material strings with weeks starting on Monday, as
/// the month grid does; the default starts them on Sunday.
class MondayFirstLocalizations extends DefaultMaterialLocalizations {
  /// Creates them.
  const new();

  /// Puts them in a `Localizations.override`.
  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _MondayFirstDelegate();

  @override
  int get firstDayOfWeekIndex => 1;
}

class _MondayFirstDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const new();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const MondayFirstLocalizations());

  @override
  bool shouldReload(_MondayFirstDelegate old) => false;
}
