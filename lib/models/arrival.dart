class Arrival {
  final String tripId;
  final String routeId;
  final String headsign;
  final Duration time; // time since midnight, can exceed 24h

  const Arrival({
    required this.tripId,
    required this.routeId,
    required this.headsign,
    required this.time,
  });

  static Duration parseTime(String s) {
    final p = s.trim().split(':');
    return Duration(
      hours: int.parse(p[0]),
      minutes: int.parse(p[1]),
      seconds: int.parse(p[2]),
    );
  }

  /// "6:05" style label, wraps past midnight.
  String get label {
    final h = time.inHours % 24;
    final m = time.inMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }
}