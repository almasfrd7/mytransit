import '../models/arrival.dart';
import '../models/gtfs_realtime.dart';
import '../models/route.dart';
import '../models/station.dart';
import '../services/gtfs_realtime_service.dart';
import '../services/transit_api.dart';

/// Reads both bundled feeds: the Klang Valley rail feed (root of GTFS/) and
/// the KTMB feed (GTFS/ktmb/). Tables only present in one feed are read from
/// wherever they exist.
const _ktmb = 'ktmb';

class TransitRepository {
  TransitRepository(this._api);
  final TransitApi _api;

  List<Station>? _stations;
  List<TransitRoute>? _routes;

  /// Read [file] from every feed that ships it (e.g. 'trips.txt',
  /// 'stop_times.txt'). Falls back silently for feeds missing the file.
  Future<List<Map<String, String>>> _readAll(String file) async {
    final out = <Map<String, String>>[];
    out.addAll(await _api.readTable(file));
    try {
      out.addAll(await _api.readTable('$_ktmb/$file'));
    } catch (_) {
      // This feed doesn't ship the file (e.g. shapes.txt for KTMB).
    }
    return out;
  }

  /// stops.txt tags Kajang Line stops as route_id "MRT", but routes.txt
  /// calls that line "KGL". Normalise it here.
  Map<String, String> _fixRow(Map<String, String> r) {
    if ((r['stop_id'] ?? '').startsWith('KG') && r['route_id'] == 'MRT') {
      return {...r, 'route_id': 'KGL'};
    }
    return r;
  }

  Future<List<Station>> getStations() async => _stations ??= await _loadStations();

  Future<List<Station>> _loadStations() async {
    // Klang Valley feed: one row per stop already carries route_id/status.
    final rapid = (await _api.readTable('stops.txt'))
        .where((r) => r['status'] == 'valid')
        .map(_fixRow)
        .map(Station.fromRow)
        .toList();

    // KTMB feed: stops.txt has no route_id or status, so derive per-route
    // rows from which trips (via stop_times) actually call there — matching
    // the interchange-row pattern of the Klang Valley feed.
    final ktmb = await _loadKtmbStations();
    return [...rapid, ...ktmb];
  }

  Future<List<Station>> _loadKtmbStations() async {
    final stops = {
      for (final r in await _api.readTable('$_ktmb/stops.txt'))
        if (r['stop_id'] != null) r['stop_id']!: r,
    };
    if (stops.isEmpty) return const [];

    final tripRoute = {
      for (final t in await _api.readTable('$_ktmb/trips.txt'))
        if (t['trip_id'] != null && t['route_id'] != null)
          t['trip_id']!: t['route_id']!,
    };

    final servedBy = <String, Set<String>>{};
    for (final st in await _api.readTable('$_ktmb/stop_times.txt')) {
      final rid = tripRoute[st['trip_id']];
      final sid = st['stop_id'];
      if (rid == null || sid == null || !stops.containsKey(sid)) continue;
      (servedBy[rid] ??= {}).add(sid);
    }

    return [
      for (final e in servedBy.entries)
        for (final sid in e.value)
          Station.fromRow({
            ...stops[sid]!,
            'category': 'KTM',
            'route_id': e.key,
          }),
    ];
  }

  Future<List<TransitRoute>> getRoutes() async => _routes ??= await _loadRoutes();

  Future<List<TransitRoute>> _loadRoutes() async {
    final rows = await _readAll('routes.txt');
    return rows
        .map((r) => r.containsKey('status')
            ? r // Klang Valley rows carry their own status/category
            : {...r, 'status': 'valid', 'category': 'KTM'})
        .where((r) => r['status'] == 'valid')
        .map(TransitRoute.fromRow)
        .toList();
  }

  Future<List<Station>> getStationsForRoute(String routeId) async =>
      (await getStations()).where((s) => s.routeId == routeId).toList();

  /// Shape polylines for [routeId] (lon/lat), keyed by shape_id and ordered
  /// by shape_pt_sequence. A route usually has two (one per direction).
  ///
  /// KTMB ships no shapes.txt, so when a route has no explicit geometry we
  /// derive a polyline from the ordered stop sequence of a representative
  /// trip per direction.
  Future<Map<String, List<({double lng, double lat})>>> getShapesForRoute(
      String routeId) async {
    final shapeIds = <String>{};
    for (final t in await _readAll('trips.txt')) {
      if (t['route_id'] != routeId) continue;
      final id = t['shape_id'];
      if (id != null && id.isNotEmpty) shapeIds.add(id);
    }

    if (shapeIds.isNotEmpty) {
      final points =
          <String, Map<int, ({double lng, double lat})>>{};
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

    return _shapesFromStops(routeId);
  }

  /// Derive polylines from stop sequences: pick a representative trip per
  /// direction and map its ordered stop_ids to coordinates.
  Future<Map<String, List<({double lng, double lat})>>> _shapesFromStops(
      String routeId) async {
    final trips = await _readAll('trips.txt');
    final repTrip = <String, String>{}; // direction -> trip_id
    for (final t in trips) {
      if (t['route_id'] != routeId) continue;
      final tid = t['trip_id'];
      if (tid == null) continue;
      repTrip.putIfAbsent(t['direction_id'] ?? '0', () => tid);
    }
    if (repTrip.isEmpty) return {};

    final coords = {
      for (final s in await getStations()) s.id: (lng: s.lng, lat: s.lat),
    };

    final wanted = repTrip.values.toSet();
    final legs = <String, Map<int, String>>{}; // trip -> seq -> stop_id
    for (final st in await _readAll('stop_times.txt')) {
      final tid = st['trip_id'];
      if (tid == null || !wanted.contains(tid)) continue;
      final sid = st['stop_id'];
      final seq = int.tryParse(st['stop_sequence'] ?? '');
      if (sid == null || seq == null) continue;
      (legs[tid] ??= {})[seq] = sid;
    }

    final out = <String, List<({double lng, double lat})>>{};
    repTrip.forEach((dir, tid) {
      final seqs = legs[tid];
      if (seqs == null) return;
      final path = <({double lng, double lat})>[
        for (final seq in seqs.keys.toList()..sort())
          if (coords[seqs[seq]] != null) coords[seqs[seq]]!,
      ];
      if (path.length >= 2) out[dir] = path;
    });
    return out;
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
      for (final t in await _readAll('trips.txt'))
        if (t['service_id'] == service) t['trip_id']!: t,
    };

    final result = <Arrival>[];
    for (final st in await _readAll('stop_times.txt')) {
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

  // Live vehicle positions

  late final GtfsRealtimeService _live = GtfsRealtimeService();

  /// The most recently fetched live positions from the GTFS-Realtime feed.
  /// Starts as `null`; becomes available after the first poll completes.
  List<VehiclePosition>? get livePositions => _live.positions;

  /// Timestamp of the most recent successful fetch, or `null`.
  DateTime? get lastLiveFetchAt => _live.lastFetchedAt;

  /// The pending fetch error, if the most recent fetch failed.
  Exception? get liveFetchError => _live.fetchError;

  /// Stream of live-position snapshots. Starts emitting once [startLivePolling]
  /// is called.
  Stream<List<VehiclePosition>> get livePositionsStream =>
      _live.positionsStream;

  /// Start polling the GTFS-Realtime vehicle-position feed.
  ///
  /// Polling runs on a 30-second timer (the feed update cadence) and is
  /// lightweight — it only keeps the most recent snapshot in memory.
  void startLivePolling() => _live.start();

  /// Stop the live feed poller.
  void stopLivePolling() => _live.stop();

  // Static trip index used to resolve live positions to lines.

  Map<String, String>? _tripRoute;

  /// `trip_id -> route_id` across all bundled feeds. The KTMB realtime feed
  /// reports trip ids but no route id, so we join against this.
  Future<Map<String, String>> getTripRouteIndex() async =>
      _tripRoute ??= {
        for (final t in await _readAll('trips.txt'))
          if (t['trip_id'] != null && t['route_id'] != null)
            t['trip_id']!: t['route_id']!,
      };

  /// Resolve [positions] against the static schedule: fill a missing
  /// [VehiclePosition.routeId] from the trip index, then keep only
  /// positions whose route exists in [knownRouteIds].
  Future<List<VehiclePosition>> resolvePositions(
    List<VehiclePosition> positions,
    Set<String> knownRouteIds,
  ) async {
    if (positions.isEmpty) return const [];
    final index = await getTripRouteIndex();
    final out = <VehiclePosition>[];
    for (final p in positions) {
      final rid = _routeIdOf(p, index);
      if (rid == null || !knownRouteIds.contains(rid)) continue;
      out.add(p.routeId == rid ? p : p.withRouteId(rid));
    }
    return out;
  }

  String? _routeIdOf(VehiclePosition p, Map<String, String> index) {
    if (p.routeId != null && p.routeId!.isNotEmpty) return p.routeId;
    if (p.tripId != null) return index[p.tripId!];
    return null;
  }
}
