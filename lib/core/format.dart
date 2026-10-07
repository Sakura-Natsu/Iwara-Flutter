import 'package:intl/intl.dart';

String formatCount(int? n) {
  if (n == null) return '0';
  if (n >= 100000000) return '${_trim(n / 100000000)}亿';
  if (n >= 10000) return '${_trim(n / 10000)}万';
  return n.toString();
}

String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatSeconds(int? seconds) =>
    seconds == null ? '' : formatDuration(Duration(seconds: seconds));

String formatAgo(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  if (t.year == DateTime.now().year) return DateFormat('MM-dd').format(t);
  return formatDate(t);
}

String formatDate(DateTime? t) =>
    t == null ? '' : DateFormat('yyyy-MM-dd').format(t.toLocal());

String formatDateTime(DateTime? t) =>
    t == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}
