class Station {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String category; // LRT, MRT, ...
  final String routeId;
  final bool isAccessible;

  const Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    required this.routeId,
    required this.isAccessible,
  });

  factory Station.fromRow(Map<String, String> r) => Station(
    id: r['stop_id']!,
    name: r['stop_name']!,
    lat: double.parse(r['stop_lat']!),
    lng: double.parse(r['stop_lon']!),
    category: r['category'] ?? '',
    routeId: r['route_id'] ?? '',
    isAccessible: (r['isOKU'] ?? '').toLowerCase() == 'true',
  );
}