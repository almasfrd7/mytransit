import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/gtfs_realtime.dart' show VehiclePosition;

/// Minimal GTFS-Realtime vehicle-position client for the Malaysia Open API.
///
/// The endpoint returns a binary `FeedMessage` protobuf, not JSON. This class
/// decodes just enough of the schema to extract vehicle positions for KTMB.
/// It does not depend on generated proto code.
///
/// Wire format (gtfs-realtime.proto):
///   FeedMessage      { header = 1, entity = 2 (repeated) }
///   FeedEntity       { id = 1, vehicle = 4 }
///   VehiclePosition  { trip = 1, position = 2, timestamp = 6,
///                      vehicle = 8 (older schema) or 9 }
///   TripDescriptor   { trip_id = 1, route_id = 5 }
///   VehicleDescriptor{ id = 1, label = 2 }
///   Position         { lat = 1 float, lng = 2 float, bearing = 3 float,
///                      speed = 5 float }
class GtfsRealtimeService {
  GtfsRealtimeService({
    this.baseUrl =
        'https://api.data.gov.my/gtfs-realtime/vehicle-position',
    this.pollInterval = const Duration(seconds: 30),
  });

  http.Client? _ownClient;

  /// HTTP client, created on first fetch so that constructing the service
  /// has no side effects (and can happen outside a test zone).
  http.Client get client => _ownClient ??= http.Client();

  final String baseUrl;
  final Duration pollInterval;

  /// Most recent decoded positions for the given agency, or `null` when no
  /// response has been fetched yet.
  List<VehiclePosition>? get positions => _positions;
  List<VehiclePosition>? _positions;

  /// Set an externally provided snapshot, e.g. from a mock in tests.
  set positions(List<VehiclePosition>? v) {
    _positions = v;
    if (v != null) {
      _controller.add(List.unmodifiable(v));
    }
  }

  /// Most recent fetch timestamp, or `null`.
  DateTime? get lastFetchedAt => _lastFetchedAt;
  DateTime? _lastFetchedAt;

  /// Most recent fetch error, or `null`.
  Exception? get fetchError => _fetchError;
  Exception? _fetchError;

  /// Most recent fetch latency, for diagnostics.
  Duration? get lastLatency => _lastLatency;
  Duration? _lastLatency;

  // --- polling ---

  final _controller =
      StreamController<List<VehiclePosition>>.broadcast();

  /// Stream of position snapshots, emitted on every successful fetch.
  Stream<List<VehiclePosition>> get positionsStream => _controller.stream;

  Timer? _timer;

  void start() {
    if (_timer != null) return;
    _fetch();
    _timer = Timer.periodic(pollInterval, (_) => _fetch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    final start = DateTime.now();
    try {
      final uri = Uri.parse('$baseUrl/ktmb/');
      final response = await client.get(uri);
      final raw = response.bodyBytes;

      _lastLatency = DateTime.now().difference(start);
      _positions = decode(raw);
      _lastFetchedAt = DateTime.now();
      _fetchError = null;
      _controller.add(List.unmodifiable(_positions!));
    } catch (e) {
      _fetchError = e is Exception ? e : Exception(e.toString());
      _lastLatency = DateTime.now().difference(start);
      // Don't clear positions on a transient failure; keep showing the
      // last good snapshot rather than an empty screen.
    }
  }

  // --- protobuf decode (minimal) ---

  /// Decode a GTFS-Realtime `FeedMessage` byte stream into vehicle positions.
  ///
  /// Public so tests and tools can decode captured payloads without hitting
  /// the network. Malformed input yields an empty list rather than throwing.
  List<VehiclePosition> decode(Uint8List bytes) {
    try {
      final feed = _readMessage(bytes);
      final now = DateTime.now();
      final entities = <VehiclePosition>[];

      for (final ent in feed) {
        if (ent.key != 2) continue; // FeedMessage.entity
        final entBytes = ent.value;
        if (entBytes == null) continue;

        for (final f in _readMessage(entBytes)) {
          if (f.key != 4 || f.value == null) continue; // FeedEntity.vehicle
          final vp = _readVehicle(f.value!, now);
          if (vp != null) entities.add(vp);
        }
      }
      return entities;
    } catch (_) {
      return [];
    }
  }

  VehiclePosition? _readVehicle(Uint8List bytes, DateTime now) {
    String? vehicleId;
    String? label;
    String? tripId;
    String? routeId;
    double lat = 0;
    double lng = 0;
    int? bearingDeg;
    double? speedMps;
    DateTime? fetchedAt;

    for (final f in _readMessage(bytes)) {
      switch (f.key) {
        case 1: // VehiclePosition.trip (TripDescriptor)
          final trip = f.value;
          if (trip != null) {
            for (final tf in _readMessage(trip)) {
              if (tf.key == 1 && tf.value != null) {
                tripId = utf8.decode(tf.value!);
              } else if (tf.key == 5 && tf.value != null) {
                routeId = utf8.decode(tf.value!);
              }
            }
          }
        case 2: // VehiclePosition.position (Position)
          final pos = f.value;
          if (pos != null) {
            for (final pf in _readMessage(pos)) {
              switch (pf.key) {
                case 1: // latitude (float)
                  lat = pf.asFloat ?? lat;
                case 2: // longitude (float)
                  lng = pf.asFloat ?? lng;
                case 3: // bearing (float)
                  bearingDeg = pf.asFloat?.round();
                case 5: // speed (float, m/s)
                  speedMps = pf.asFloat;
              }
            }
          }
        case 8: // VehiclePosition.vehicle (VehicleDescriptor, older schema)
        case 9: // VehiclePosition.vehicle (newer schema)
          final desc = f.value;
          if (desc != null && vehicleId == null) {
            for (final df in _readMessage(desc)) {
              if (df.key == 1 && df.value != null) {
                vehicleId = utf8.decode(df.value!);
              } else if (df.key == 2 && df.value != null) {
                label = utf8.decode(df.value!);
              }
            }
          }
        case 5: // VehiclePosition.timestamp (this feed) / current_status
        case 6: // VehiclePosition.timestamp (standard schema)
          final ts = f.asInt;
          if (ts != null && ts > 1000000000 && ts < 4102444800) {
            fetchedAt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
      }
    }

    // Transponders occasionally report a null fix (0,0); such a marker has
    // no meaningful place on the map, so drop the vehicle entirely.
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return null;

    // The feed reports a constant placeholder speed (90 m/s ≈ 324 km/h)
    // for every vehicle; treat anything above real rail limits (180 km/h)
    // as unknown rather than displaying it.
    if (speedMps != null && speedMps > 50) speedMps = null;

    // Some feeds omit the vehicle descriptor; fall back to the trip id.
    vehicleId ??= tripId;
    if (vehicleId == null) return null;

    return VehiclePosition(
      vehicleId: vehicleId,
      label: label,
      tripId: tripId,
      routeId: routeId,
      lat: lat,
      lng: lng,
      bearingDeg: bearingDeg,
      speedMps: speedMps,
      fetchedAt: fetchedAt ?? now,
    );
  }

  /// Parse one protobuf message body into `(fieldNumber, value)` entries.
  /// `value` is `Uint8List` for length-delimited fields, `int` for varints,
  /// `double` for 32/64-bit floats.
  List<(int, Object?)> _readMessage(Uint8List bytes) {
    final out = <(int, Object?)>[];
    var i = 0;

    int? readVarInt() {
      int result = 0;
      var shift = 0;
      while (i < bytes.length) {
        final b = bytes[i++];
        result |= (b & 0x7f) << shift;
        if ((b & 0x80) == 0) return result;
        shift += 7;
        if (shift > 63) return result;
      }
      return null;
    }

    while (i < bytes.length) {
      final tag = readVarInt();
      if (tag == null) break;
      final field = tag >> 3;
      final wire = tag & 0x7;

      switch (wire) {
        case 0: // varint
          final v = readVarInt();
          if (v == null) return out;
          out.add((field, v));
        case 1: // 64-bit (little-endian in protobuf)
          if (i + 8 > bytes.length) return out;
          final d = ByteData.sublistView(bytes, i, i + 8)
              .getFloat64(0, Endian.little);
          i += 8;
          out.add((field, d));
        case 2: // length-delimited
          final len = readVarInt();
          if (len == null || i + len > bytes.length) return out;
          out.add((field, Uint8List.sublistView(bytes, i, i + len)));
          i += len;
        case 5: // 32-bit (little-endian in protobuf)
          if (i + 4 > bytes.length) return out;
          final f = ByteData.sublistView(bytes, i, i + 4)
              .getFloat32(0, Endian.little);
          i += 4;
          out.add((field, f));
        default:
          return out; // unknown wire type — stop rather than misparse
      }
    }
    return out;
  }
}

extension PbFieldAccess on (int, Object?) {
  int get key => $1;
  Object? get raw => $2;
  int? get asInt => $2 is int ? $2 as int : null;
  double? get asFloat => $2 is double ? $2 as double : null;
  Uint8List? get value => $2 is Uint8List ? $2 as Uint8List : null;
}
