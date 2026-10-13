import '../models/arrival.dart';
import '../models/gtfs_realtime.dart';
import '../models/route.dart';
import '../models/service_status.dart';
import '../models/station.dart';
import '../services/advisory_service.dart';
import '../services/gtfs_realtime_service.dart';
import '../services/transit_api.dart';

/// Reads both bundled feeds: the Klang Valley rail feed (root of GTFS/) and
/// the KTMB feed (GTFS/ktmb/). Tables only present in one feed are read from
/// wherever they exist.
const _ktmb = 'ktmb';

class _StopTime {
  const _StopTime(this.tripId, this.seq, this.time);
  final String tripId;
  final int seq;
  final Duration time;
}

class _Freq {
  const _Freq(this.start, this.end, this.headwaySecs);
  final Duration start;
  final Duration end;
  final int headwaySecs;
}

/// Everything needed to answer "next trains at stop X" without reparsing.
class _ScheduleIndex {
  _ScheduleIndex({
    required this.byStop,
    required this.trips,
    required this.tripStart,
    required this.tripEnd,
    required this.tripLastSeq,
    required this.tripLastStop,
    required this.freqs,
    required this.stopNames,
  });

  final Map<String, List<_StopTime>> byStop;
  final Map<String, Map<String, String>> trips;
  final Map<String, Duration> tripStart; // time at first stop
  final Map<String, Duration> tripEnd; // time at last stop
  final Map<String, int> tripLastSeq;
  final Map<String, String> tripLastStop;
  final Map<String, List<_Freq>> freqs;
  final Map<String, String> stopNames;
}

class TransitRepository {
  TransitRepository(this._api, {AdvisoryService? advisories})
      : _advisories = advisories ?? AdvisoryService();

  final TransitApi _api;
  final AdvisoryService _advisories;

  List<Station>? _stations;
  List<TransitRoute>? _routes;

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

  Future<List<Station>> getStations() async =>
      _stations ??= await _loadStations();

  Future<List<Station>> _loadStations() async {
    final rapid = (await _api.readTable('stops.txt'))
        .where((r) => r['status'] == 'valid')
        .map(_fixRow)
        .map(Station.fromRow)
        .toList();

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

  Future<List<TransitRoute>> getRoutes() async =>
      _routes ??= await _loadRoutes();

  Future<List<TransitRoute>> _loadRoutes() async {
    final rows = await _readAll('routes.txt');
    return rows
        .map((r) => r.containsKey('status')
        ? r
        : {...r, 'status': 'valid', 'category': 'KTM'})
        .where((r) => r['status'] == 'valid')
        .map(TransitRoute.fromRow)
        .toList();
  }

  Future<List<Station>> getStationsForRoute(String routeId) async =>
      (await getStations()).where((s) => s.routeId == routeId).toList();

  /// Shape polylines for [routeId] (lon/lat), keyed by shape_id and ordered
  /// by shape_pt_sequence. KTMB ships no shapes.txt, so geometry is derived
  /// from the stop sequence of a representative trip per direction.
  Future<Map<String, List<({double lng, double lat})>>> getShapesForRoute(
      String routeId) async {
    final shapeIds = <String>{};
    for (final t in await _readAll('trips.txt')) {
      if (t['route_id'] != routeId) continue;
      final id = t['shape_id'];
      if (id != null && id.isNotEmpty) shapeIds.add(id);
    }

    if (shapeIds.isNotEmpty) {
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

    return _shapesFromStops(routeId);
  }

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
    final legs = <String, Map<int, String>>{};
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

  // ───────────────────────── Schedule ─────────────────────────

  Future<_ScheduleIndex>? _scheduleFuture;
  Future<_ScheduleIndex> _schedule() => _scheduleFuture ??= _loadSchedule();

  static Duration? _tryTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Arrival.parseTime(raw);
    } catch (_) {
      return null;
    }
  }

  Future<_ScheduleIndex> _loadSchedule() async {
    final trips = <String, Map<String, String>>{};
    for (final t in await _readAll('trips.txt')) {
      final id = t['trip_id'];
      if (id != null) trips[id] = t;
    }

    final stopNames = <String, String>{};
    for (final s in await _readAll('stops.txt')) {
      final id = s['stop_id'];
      final name = s['stop_name'];
      if (id != null && name != null) stopNames[id] = name.trim();
    }

    final byStop = <String, List<_StopTime>>{};
    final tripStart = <String, Duration>{};
    final tripEnd = <String, Duration>{};
    final firstSeq = <String, int>{};
    final lastSeq = <String, int>{};
    final lastStop = <String, String>{};

    for (final st in await _readAll('stop_times.txt')) {
      final tid = st['trip_id'];
      final sid = st['stop_id'];
      final seq = int.tryParse(st['stop_sequence'] ?? '');
      final time = _tryTime(st['arrival_time']);
      if (tid == null || sid == null || seq == null || time == null) continue;

      (byStop[sid] ??= []).add(_StopTime(tid, seq, time));

      final fs = firstSeq[tid];
      if (fs == null || seq < fs) {
        firstSeq[tid] = seq;
        tripStart[tid] = time;
      }
      final ls = lastSeq[tid];
      if (ls == null || seq > ls) {
        lastSeq[tid] = seq;
        lastStop[tid] = sid;
        tripEnd[tid] = time;
      }
    }

    // Klang Valley lines are defined by headways, not individual trips.
    final freqs = <String, List<_Freq>>{};
    try {
      for (final f in await _api.readTable('frequencies.txt')) {
        final tid = f['trip_id'];
        final start = _tryTime(f['start_time']);
        final end = _tryTime(f['end_time']);
        final headway = int.tryParse(f['headway_secs'] ?? '');
        if (tid == null || start == null || end == null) continue;
        if (headway == null || headway <= 0) continue;
        (freqs[tid] ??= []).add(_Freq(start, end, headway));
      }
    } catch (_) {
      // No frequencies bundled: fall back to fixed trip times.
    }

    return _ScheduleIndex(
      byStop: byStop,
      trips: trips,
      tripStart: tripStart,
      tripEnd: tripEnd,
      tripLastSeq: lastSeq,
      tripLastStop: lastStop,
      freqs: freqs,
      stopNames: stopNames,
    );
  }

  /// Whether a GTFS service id runs on [d]. KTMB uses its own ids.
  static bool _runsOn(String serviceId, DateTime d) {
    final weekend = d.weekday >= DateTime.saturday;
    return switch (serviceId) {
      'MonFri' || 'komuter_weekday' => !weekend,
      'Sat' => d.weekday == DateTime.saturday,
      'Sun' => d.weekday == DateTime.sunday,
      'komuter_weekend' => weekend,
      _ => true, // ets, intercity, shuttle_selatan, komuter_utara…
    };
  }

  /// Next scheduled arrivals at a station (timetable, not live).
  ///
  /// Pass [routeId] to only list one line (needed at shared KTMB stops).
  Future<List<Arrival>> getNextArrivals(
      String stopId, {
        DateTime? now,
        int limit = 5,
        String? routeId,
      }) async {
    now ??= DateTime.now();
    final idx = await _schedule();
    final nowOffset = Duration(
      hours: now.hour,
      minutes: now.minute,
      seconds: now.second,
    );

    final result = <Arrival>[];
    for (final st in idx.byStop[stopId] ?? const <_StopTime>[]) {
      final trip = idx.trips[st.tripId];
      if (trip == null) continue;
      if (routeId != null && trip['route_id'] != routeId) continue;
      if (!_runsOn(trip['service_id'] ?? '', now)) continue;
      // Trains terminating here don't "depart" from this station.
      if (st.seq == idx.tripLastSeq[st.tripId]) continue;

      var headsign = trip['trip_headsign'] ?? '';
      if (headsign.isEmpty) {
        final name = idx.stopNames[idx.tripLastStop[st.tripId]];
        headsign = name == null ? '' : 'To $name';
      }
      final rid = trip['route_id'] ?? '';

      final windows = idx.freqs[st.tripId];
      if (windows == null) {
        if (st.time < nowOffset) continue;
        result.add(Arrival(
          tripId: st.tripId,
          routeId: rid,
          headsign: headsign,
          time: st.time,
        ));
        continue;
      }

      // Frequency-based: expand the headway windows into concrete times.
      final offset = st.time - (idx.tripStart[st.tripId] ?? st.time);
      for (final w in windows) {
        final gap = Duration(seconds: w.headwaySecs);
        final sinceStart = nowOffset - offset - w.start;
        var k = sinceStart.isNegative
            ? 0
            : (sinceStart.inSeconds + w.headwaySecs - 1) ~/ w.headwaySecs;
        for (var n = 0; n < limit; n++, k++) {
          final runStart = w.start + gap * k;
          if (runStart >= w.end) break;
          result.add(Arrival(
            tripId: st.tripId,
            routeId: rid,
            headsign: headsign,
            time: runStart + offset,
          ));
        }
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result.take(limit).toList();
  }

  // ───────────────────────── Service status ─────────────────────────

  /// Advisories that are active at [now].
  Future<List<Advisory>> getAdvisories({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final all = await _advisories.load();
    return all.where((a) => a.activeAt(t)).toList();
  }

  Future<ServiceStatus> getServiceStatus(
      TransitRoute route, {
        DateTime? now,
      }) async {
    final t = now ?? DateTime.now();
    final idx = await _schedule();
    final adv = [
      for (final a in await getAdvisories(now: t))
        if (a.appliesTo(route.id)) a,
    ];
    return _computeStatus(route, idx, t, adv);
  }

  Future<List<ServiceStatus>> getServiceStatuses({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final idx = await _schedule();
    final adv = await getAdvisories(now: t);
    final routes = await getRoutes();
    return [
      for (final r in routes)
        _computeStatus(r, idx, t, [
          for (final a in adv)
            if (a.appliesTo(r.id)) a,
        ]),
    ];
  }

  ServiceStatus _computeStatus(
      TransitRoute route,
      _ScheduleIndex idx,
      DateTime now,
      List<Advisory> advisories,
      ) {
    final nowOff = Duration(
      hours: now.hour,
      minutes: now.minute,
      seconds: now.second,
    );

    final windows = <_Freq>[];
    final departures = <Duration>[];
    Duration? first;
    Duration? last;

    for (final e in idx.trips.entries) {
      final trip = e.value;
      if (trip['route_id'] != route.id) continue;
      if (!_runsOn(trip['service_id'] ?? '', now)) continue;

      Duration a;
      Duration b;
      final f = idx.freqs[e.key];
      if (f != null && f.isNotEmpty) {
        windows.addAll(f);
        a = f.first.start;
        b = f.first.end;
        for (final w in f) {
          if (w.start < a) a = w.start;
          if (w.end > b) b = w.end;
        }
      } else {
        final s = idx.tripStart[e.key];
        final en = idx.tripEnd[e.key];
        if (s == null || en == null) continue;
        departures.add(s);
        a = s;
        b = en;
      }
      if (first == null || a < first) first = a;
      if (last == null || b > last) last = b;
    }

    ServiceLevel level;
    String headline;
    String? detail;
    int? hMin;
    int? hMax;

    final f0 = first;
    final l0 = last;
    if (f0 == null || l0 == null) {
      level = ServiceLevel.closed;
      headline = 'No trains scheduled today';
      detail = null;
    } else {
      // After midnight, "now" is compared against the service day's
      // 24h+ times (e.g. a 00:30 last train is stored as 24:30).
      final cmp = (now.hour < 4 && l0 >= const Duration(hours: 24))
          ? nowOff + const Duration(hours: 24)
          : nowOff;

      if (cmp < f0) {
        level = ServiceLevel.closed;
        headline = 'Not in service yet';
        detail = 'First train at ${ServiceStatus.clock(f0)}';
      } else if (cmp > l0) {
        level = ServiceLevel.closed;
        headline = 'Service has ended for today';
        detail = 'Last train around ${ServiceStatus.clock(l0)}';
      } else if (windows.isNotEmpty) {
        final current =
        windows.where((w) => cmp >= w.start && cmp < w.end).toList();
        if (current.isEmpty) {
          level = ServiceLevel.normal;
          headline = 'Running';
          detail = null;
        } else {
          int mins(_Freq w) => (w.headwaySecs / 60).round();
          final lo = current.map(mins).reduce((x, y) => x < y ? x : y);
          final hi = current.map(mins).reduce((x, y) => x > y ? x : y);
          final best = windows.map(mins).reduce((x, y) => x < y ? x : y);
          hMin = lo;
          hMax = hi;
          final off = lo > best;
          level = off ? ServiceLevel.offPeak : ServiceLevel.normal;
          headline = off ? 'Off-peak service' : 'Running normally';
          detail = hMin == hMax
              ? 'A train every $lo min'
              : 'A train every $lo–$hi min';
        }
      } else {
        // Timetable-based (KTMB): show the next departure from the origin.
        Duration? next;
        for (final d in departures) {
          if (d >= cmp && (next == null || d < next)) next = d;
        }
        level = ServiceLevel.normal;
        headline = 'Trains in service';
        detail = next == null
            ? 'No more departures from the origin station today'
            : 'Next departure at ${ServiceStatus.clock(next)}';
      }
    }

    // Published advisories override the timetable-derived status.
    final blocking =
    advisories.where((a) => a.severity != AdvisorySeverity.info).toList();
    if (blocking.isNotEmpty) {
      final worst = blocking.firstWhere(
            (a) => a.severity == AdvisorySeverity.disruption,
        orElse: () => blocking.first,
      );
      level = ServiceLevel.advisory;
      headline = worst.title;
      if (worst.message.isNotEmpty) detail = worst.message;
    }

    return ServiceStatus(
      route: route,
      level: level,
      headline: headline,
      detail: detail,
      headwayMin: hMin,
      headwayMax: hMax,
      firstTrain: first,
      lastTrain: last,
      advisories: advisories,
    );
  }

  // ───────────────────────── Live vehicles ─────────────────────────

  late final GtfsRealtimeService _live = GtfsRealtimeService();

  List<VehiclePosition>? get livePositions => _live.positions;
  DateTime? get lastLiveFetchAt => _live.lastFetchedAt;
  Exception? get liveFetchError => _live.fetchError;

  Stream<List<VehiclePosition>> get livePositionsStream =>
      _live.positionsStream;

  void startLivePolling() => _live.start();
  void stopLivePolling() => _live.stop();

  Map<String, String>? _tripRoute;

  /// `trip_id -> route_id` across all bundled feeds.
  Future<Map<String, String>> getTripRouteIndex() async => _tripRoute ??= {
    for (final t in await _readAll('trips.txt'))
      if (t['trip_id'] != null && t['route_id'] != null)
        t['trip_id']!: t['route_id']!,
  };

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