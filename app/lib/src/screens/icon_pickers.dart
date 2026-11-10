/// The app's date and time pickers. They paint numerals and icons only (the
/// textgate rule); the Material ones paint "Select date", "Cancel" and "OK".
library;

import 'package:book_guard_app/src/screens/icon_date_dialog.dart';
import 'package:book_guard_app/src/screens/icon_time_dialog.dart';
import 'package:flutter/material.dart';

/// Opens a month grid on [initialDate]; resolves to the picked day (local,
/// date only) on the check icon, or `null` on close or dismiss.
Future<DateTime?> showIconDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) =>
      IconDateDialog(initial: initialDate, first: firstDate, last: lastDate),
);

/// Opens one dialog with a start and an end time; resolves to both on the
/// check icon, or `null` on close or dismiss. An end before the start is
/// returned as is: the caller rolls it to the next day (`onDayOf`).
Future<({TimeOfDay start, TimeOfDay end})?> showIconTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
}) => showDialog<({TimeOfDay start, TimeOfDay end})>(
  context: context,
  builder: (_) =>
      IconTimeRangeDialog(initialStart: initialStart, initialEnd: initialEnd),
);
