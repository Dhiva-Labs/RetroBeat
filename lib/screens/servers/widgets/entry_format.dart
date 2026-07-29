/// Human-readable byte count, e.g. `4.2 MB`.
///
/// Null renders as an em dash rather than `0 B`: a WebDAV collection (or a
/// server that omits the header) has no length to report, and `0 B` would
/// read as an empty file instead of an unknown size.
String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';

  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = value < 10 ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

/// `12 Mar 2024` — no `intl` dependency in this project, so this is written
/// out by hand rather than pulling one in for a single date format.
String formatEntryDate(DateTime dateTime) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = dateTime.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
