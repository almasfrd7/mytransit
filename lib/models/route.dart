class TransitRoute {
  final String id;
  final String shortName;
  final String longName;
  final String description;
  final String category;
  final int colorValue; // use Color(colorValue)
  final int textColorValue;

  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.description,
    required this.category,
    required this.colorValue,
    required this.textColorValue,
  });

  static int _hex(String? s, int fallback) {
    if (s == null || s.isEmpty) return fallback;
    return int.tryParse('FF${s.replaceAll('#', '')}', radix: 16) ?? fallback;
  }

  factory TransitRoute.fromRow(Map<String, String> r) => TransitRoute(
    id: r['route_id']!,
    shortName: r['route_short_name'] ?? '',
    longName: r['route_long_name'] ?? '',
    description: r['route_desc'] ?? '',
    category: r['category'] ?? '',
    colorValue: _hex(r['route_color'], 0xFF607D8B),
    textColorValue: _hex(r['route_text_color'], 0xFFFFFFFF),
  );
}