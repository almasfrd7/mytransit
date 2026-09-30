class Station {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const Station({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory Station.fromCsv(List<dynamic> row) {
    return Station(
      id: row[0].toString(),
      name: row[2].toString(),
      latitude: double.parse(row[4].toString()),
      longitude: double.parse(row[5].toString()),
    );
  }
}