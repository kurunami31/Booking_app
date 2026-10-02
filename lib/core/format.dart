/// Formatting helpers.
library;

String formatPeso(num? amount) {
  final value = (amount ?? 0).toDouble();
  final hasCents = (value * 100).round() % 100 != 0;
  final text = value.toStringAsFixed(hasCents ? 2 : 0);
  final withSeparators = text.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'PHP $withSeparators';
}

String formatDistanceKm(double? km) {
  if (km == null) return '—';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

String formatDateTime(DateTime? dt) {
  if (dt == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = dt.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, $hour:$minute $period';
}

String formatRelative(DateTime? dt) {
  if (dt == null) return '—';
  final diff = DateTime.now().difference(dt.toLocal());
  final mins = diff.inMinutes;
  if (mins.abs() < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  final hours = diff.inHours;
  if (hours < 24) return '$hours hr ago';
  return '${diff.inDays} d ago';
}

String shortId(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

double? minutesSince(DateTime? dt) => dt == null
    ? null
    : DateTime.now().difference(dt.toLocal()).inSeconds / 60.0;
