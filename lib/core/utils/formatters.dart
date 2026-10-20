String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final precision = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

String formatDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final minutes = duration.inMinutes;
  final remaining = duration.inSeconds - minutes * 60;
  return '${minutes}m ${remaining}s';
}

String formatPages(int pages) => pages == 1 ? '1 page' : '$pages pages';
