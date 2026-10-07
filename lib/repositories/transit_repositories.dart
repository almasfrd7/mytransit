import '../models/arrival.dart';
import '../models/route.dart';
import '../models/station.dart';
import '../services/transit_api.dart';

class TransitRepository {
  TransitRepository(this._api);
  final TransitApi _api;

  List<Station>? _stations;
  List<TransitRoute>? _routes;

  /// stops.txt tags Kajang Line stops as route_id "MRT", but routes.txt
  /// calls that line "KGL". Normalise it here.
  Map<String, String> _fixRow(Map<String, String> r) {
    if ((r['stop_id'] ?? '').startsWith('KG') && r['route_id'] == 'MRT') {
      return {...r, 'route_id': 'KGL'};
    }
    return r;
  }

  Future<List<Station>> getStations() async {
    return _stations ??= (await _api.readTable('stops.txt'))
        .where((r) => r['status'] == 'valid')
        .map(_fixRow)
        .map(Station.fromRow)
        .toList();
  }

  Future<List<TransitRoute>> getRoutes() async {
    return _routes ??= (await _api.readTable('routes.txt'))
        .where((r) => r['status'] == 'valid')
        .map(TransitRoute.fromRow)
        .toList();
  }

  Future<List<Station>> getStationsForRoute(String routeId) async =>
      (await getStations()).where((s) => s.routeId == routeId).toList();

  /// Shape polylines for [routeId] (lon/lat), keyed by shape_id and ordered
  /// by shape_pt_sequence. A route usually has two (one per direction).
  Future<Map<String, List<({double lng, double lat})>>> getShapesForRoute(
      String routeId) async {
    final shapeIds = <String>{};
    for (final t in await _api.readTable('trips.txt')) {
      if (t['route_id'] != routeId) continue;
      final id = t['shape_id'];
      if (id != null && id.isNotEmpty) shapeIds.add(id);
    }
    if (shapeIds.isEmpty) return {};

    final points = <String, Map<int, ({double lng, double lat})>>{};
    for (final p in await _api.readTable('shapes.txt')) {
      final id = p['shape_id'];
      if (id == null || !shapeIds.contains(id)) continue;
      final lng = double.tryParse(p['shape_pt_lon'] ?? '');
      final lat = double.tryParse(p['shape_pt_lat'] ?? '');
      final seq = int.tryParse(p['shape_pt_sequence'] ?? '');
      if (lng == null || lat == null || seq == null) continue;
      (points[id] ??= {})[seq] = (lng: lng, lat: lat);
    }

    return {
      for (final e in points.entries)
        e.key: [
          for (final seq in e.value.keys.toList()..sort()) e.value[seq]!,
        ],
    };
  }

  static String _serviceId(DateTime d) => switch (d.weekday) {
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => 'MonFri',
  };

  /// Next scheduled arrivals at a station (timetable, not live).
  Future<List<Arrival>> getNextArrivals(
      String stopId, {
        DateTime? now,
        int limit = 5,
      }) async {
    now ??= DateTime.now();
    final service = _serviceId(now);
    final nowOffset = Duration(
      hours: now.hour,
      minutes: now.minute,
      seconds: now.second,
    );



    final trips = {
      for (final t in await _api.readTable('trips.txt'))
        if (t['service_id'] == service) t['trip_id']!: t,
    };

    final result = <Arrival>[];
    for (final st in await _api.readTable('stop_times.txt')) {
      if (st['stop_id'] != stopId) continue;
      final trip = trips[st['trip_id']];
      if (trip == null) continue;
      final t = Arrival.parseTime(st['arrival_time']!);
      if (t < nowOffset) continue;
      result.add(Arrival(
        tripId: st['trip_id']!,
        routeId: trip['route_id']!,
        headsign: trip['trip_headsign'] ?? '',
        time: t,
      ));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result.take(limit).toList();
  }
}