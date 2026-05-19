String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  if (unit == 0) {
    return '${size.toStringAsFixed(0)} ${units[unit]}';
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
}

String formatSpeed(num bytesPerSecond) {
  if (bytesPerSecond <= 0) {
    return '--';
  }
  return '${formatBytes(bytesPerSecond)}/s';
}

String formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
