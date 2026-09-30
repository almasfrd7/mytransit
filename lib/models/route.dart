class TransitRoute {
  final String id;
  final String shortName;
  final String longName;

  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
  });

  factory TransitRoute.fromCsv(Map<String, dynamic> row) {
    return TransitRoute(
      id: row['route_id']?.toString() ?? '',
      shortName: row['route_short_name']?.toString() ?? '',
      longName: row['route_long_name']?.toString() ?? '',
    );
  }
}