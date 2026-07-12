/// Formats a Duration to mm:ss
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Formats milliseconds to mm:ss
String formatMilliseconds(int? milliseconds) {
  if (milliseconds == null) return '00:00';
  return formatDuration(Duration(milliseconds: milliseconds));
}
