/// [moment] as ISO-8601 local time with its UTC offset
/// (`2026-11-08T09:30:00+01:00`) -- the PC reads the wall clock and the zone
/// from the one string.
String isoWithOffset(DateTime moment) {
  final local = moment.toLocal();
  final offset = local.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  final wall = local.toIso8601String().split('.').first;
  return '$wall$sign$hh:$mm';
}
