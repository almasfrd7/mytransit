/// One decoded vehicle-position entity from a GTFS-Realtime feed.
///
/// Fields come from the standard GTFS-Realtime `VehiclePosition` message:
/// vehicle id, optional trip/route ids, position (lat/lng/bearing/speed),
/// and the feed's own timestamp when it reported one.
class VehiclePosition {
  final String vehicleId;
  final String? label;
  final String? tripId;
  final String? routeId;
  final double lat;
  final double lng;
  final int? bearingDeg;
  final double? speedMps;
  final DateTime fetchedAt;

  const VehiclePosition({
    required this.vehicleId,
    this.label,
    this.tripId,
    this.routeId,
    required this.lat,
    required this.lng,
    this.bearingDeg,
    this.speedMps,
    required this.fetchedAt,
  });

  /// Copy with [routeId] resolved (the feed often omits it; trip ids join
  /// against the static schedule instead).
  VehiclePosition withRouteId(String? id) => VehiclePosition(
        vehicleId: vehicleId,
        label: label,
        tripId: tripId,
        routeId: id,
        lat: lat,
        lng: lng,
        bearingDeg: bearingDeg,
        speedMps: speedMps,
        fetchedAt: fetchedAt,
      );

  /// Bearing in degrees, or `null` when the feed did not report one.
  double? get bearing => bearingDeg?.toDouble();

  /// Speed in metres per second, or `null` when the feed did not report one.
  double? get speed => speedMps;

  /// Display name: train label (e.g. "ETS304") when present, else id.
  String get displayName =>
      (label != null && label!.isNotEmpty) ? label! : vehicleId;

  /// Bearing as a compass heading string, e.g. `"ENE"` or `"N"`.
  String compassHeading() {
    final b = bearingDeg ?? 0;
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final idx = ((b + 11.25) % 360) ~/ 22.5;
    return dirs[idx];
  }

  /// Human-readable speed in km/h, or an empty string when unknown.
  String speedKmhLabel() {
    final s = speed;
    if (s == null) return '';
    return '${(s * 3.6).round()} km/h';
  }
}
