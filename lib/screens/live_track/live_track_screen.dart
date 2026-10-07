import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/gtfs_realtime.dart';
import '../../models/route.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/transit_api.dart';

/// Draws a line's shape with its stations and overlays live vehicle markers.
class LiveTrackScreen extends StatefulWidget {
  const LiveTrackScreen({super.key, this.repo});

  /// Reuse a repository so GTFS tables are only parsed once per session.
  final TransitRepository? repo;

  @override
  State<LiveTrackScreen> createState() => _LiveTrackScreenState();
}

class _LiveTrackScreenState extends State<LiveTrackScreen>
    with SingleTickerProviderStateMixin {
  late final TransitRepository _repo =
      widget.repo ?? TransitRepository(TransitApi());

  late final Future<({List<TransitRoute> routes})> _data = () async {
    final routes = await _repo.getRoutes();
    return (routes: routes);
  }();

  final Map<String, Future<_TrackData>> _tracks = {};
  String? _routeId;
  bool _userPicked = false;
  StreamSubscription<List<VehiclePosition>>? _liveSub;

  late final AnimationController _marker;

  Future<_TrackData> _trackFor(TransitRoute r) => _tracks[r.id] ??= () async {
        final shapes = await _repo.getShapesForRoute(r.id);
        final stations = await _repo.getStationsForRoute(r.id);
        return _TrackData(r, shapes.values.toList(), stations);
      }();

  @override
  void initState() {
    super.initState();
    _marker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
    _marker.repeat();
    // Kick off the KTMB feed poller (30s cadence) for this screen.
    _repo.startLivePolling();
    // Until the user picks a line, follow whichever line has live vehicles
    // (the feed is KTMB-only today, so the default RapidKL line would
    // otherwise always look empty).
    _liveSub = _repo.livePositionsStream.listen(_followLiveVehicles);
  }

  Future<void> _followLiveVehicles(List<VehiclePosition> pos) async {
    if (!mounted || _userPicked || pos.isEmpty) return;
    final idx = await _repo.getTripRouteIndex();
    if (!mounted || _userPicked) return;

    String? ridOf(VehiclePosition p) {
      if (p.routeId != null && p.routeId!.isNotEmpty) return p.routeId;
      return p.tripId != null ? idx[p.tripId!] : null;
    }

    final current = _routeId;
    if (current != null && pos.any((p) => ridOf(p) == current)) return;
    String? target;
    for (final p in pos) {
      final rid = ridOf(p);
      if (rid != null) {
        target = rid;
        break;
      }
    }
    if (target != null) setState(() => _routeId = target);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _repo.stopLivePolling();
    _marker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live track')),
      body: FutureBuilder<({List<TransitRoute> routes})>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load: ${snap.error}'));
          }
          final routes = snap.data!.routes;
          if (routes.isEmpty) {
            return const Center(child: Text('No lines available.'));
          }
          final route = routes.firstWhere(
            (r) => r.id == _routeId,
            orElse: () => routes.first,
          );

          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  children: [
                    for (final r in routes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 6,
                            backgroundColor: Color(r.colorValue),
                          ),
                          label: Text(r.shortName),
                          selected: r.id == route.id,
                          onSelected: (_) {
                            _userPicked = true;
                            setState(() => _routeId = r.id);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<_TrackData>(
                  future: _trackFor(route),
                  builder: (context, t) {
                    if (t.hasError) {
                      return Center(
                          child: Text('Could not load map: ${t.error}'));
                    }
                    if (!t.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final data = t.data!;
                    if (data.shapes.isEmpty) {
                      return const Center(
                        child: Text('No map geometry for this line yet.'),
                      );
                    }
                    final knownIds = routes.map((r) => r.id).toSet();
                    return StreamBuilder<List<VehiclePosition>>(
                      stream: _repo.livePositionsStream,
                      builder: (context, live) {
                        final raw = live.data ??
                            _repo.livePositions ??
                            const <VehiclePosition>[];
                        return _TrackBody(
                          repo: _repo,
                          data: data,
                          rawPositions: raw,
                          knownRouteIds: knownIds,
                          animation: _marker,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Map + live vehicles + info, with live positions resolved against the
/// static schedule before rendering.
class _TrackBody extends StatelessWidget {
  const _TrackBody({
    required this.repo,
    required this.data,
    required this.rawPositions,
    required this.knownRouteIds,
    required this.animation,
  });

  final TransitRepository repo;
  final _TrackData data;
  final List<VehiclePosition> rawPositions;
  final Set<String> knownRouteIds;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VehiclePosition>>(
      future: repo.resolvePositions(rawPositions, knownRouteIds),
      builder: (context, snap) {
        final resolved = snap.data ?? const <VehiclePosition>[];
        final mine =
            resolved.where((p) => p.routeId == data.route.id).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: _TrackMap(
                  data: data,
                  animation: animation,
                  livePositions: mine,
                ),
              ),
              const SizedBox(height: 12),
              _LiveCard(
                route: data.route,
                repo: repo,
                positions: mine,
                networkCount: resolved.length,
              ),
              _TrackInfo(data: data),
            ],
          ),
        );
      },
    );
  }
}

class _TrackData {
  _TrackData(this.route, this.shapes, this.stations);
  final TransitRoute route;
  final List<List<({double lng, double lat})>> shapes;
  final List<Station> stations;
}

// Map

class _TrackMap extends StatelessWidget {
  const _TrackMap({
    required this.data,
    required this.animation,
    required this.livePositions,
  });

  final _TrackData data;
  final Animation<double> animation;
  final List<VehiclePosition> livePositions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _TrackPainter(
                shapes: data.shapes,
                stations: data.stations,
                color: Color(data.route.colorValue),
                dotFill: cs.surface,
                progress: animation.value,
                livePositions: livePositions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.shapes,
    required this.stations,
    required this.color,
    required this.dotFill,
    this.progress = 0,
    this.livePositions = const [],
  });

  final List<List<({double lng, double lat})>> shapes;
  final List<Station> stations;
  final Color color;
  final Color dotFill;
  final double progress;

  /// Real vehicles from the GTFS-Realtime feed for this line. When non-empty
  /// they replace the preview marker animation.
  final List<VehiclePosition> livePositions;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapes.isEmpty || size.isEmpty) return;

    double minLng = double.infinity,
        maxLng = double.negativeInfinity;
    double minLat = double.infinity,
        maxLat = double.negativeInfinity;
    void grow(double lng, double lat) {
      minLng = math.min(minLng, lng);
      maxLng = math.max(maxLng, lng);
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
    }

    for (final path in shapes) {
      for (final p in path) {
        grow(p.lng, p.lat);
      }
    }
    for (final s in stations) {
      grow(s.lng, s.lat);
    }

    final spanLng = maxLng - minLng;
    final spanLat = maxLat - minLat;
    if (spanLng <= 0 || spanLat <= 0) return;

    const pad = 22.0;
    final scale = math.min(
      (size.width - 2 * pad) / spanLng,
      (size.height - 2 * pad) / spanLat,
    );
    if (!scale.isFinite || scale <= 0) return;

    final dx = (size.width - spanLng * scale) / 2;
    final dy = (size.height - spanLat * scale) / 2;
    Offset proj(double lng, double lat) =>
        Offset(dx + (lng - minLng) * scale, dy + (maxLat - lat) * scale);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.22);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final path in shapes) {
      if (path.length < 2) continue;
      final geo = Path();
      for (var i = 0; i < path.length; i++) {
        final p = proj(path[i].lng, path[i].lat);
        if (i == 0) {
          geo.moveTo(p.dx, p.dy);
        } else {
          geo.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(geo, halo);
      canvas.drawPath(geo, line);
    }

    final fill = Paint()..color = dotFill;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final s in stations) {
      final p = proj(s.lng, s.lat);
      canvas.drawCircle(p, 5.5, fill);
      canvas.drawCircle(p, 5.5, ring);
    }

    if (livePositions.isNotEmpty) {
      // Real vehicles from the feed.
      for (final v in livePositions) {
        _drawMarker(canvas, proj(v.lng, v.lat));
      }
      return;
    }

    // Preview marker gliding along the route until live data arrives.
    final path = [
      for (final p in shapes.first) proj(p.lng, p.lat),
    ];
    if (path.isEmpty) return;
    _drawMarker(canvas, _pointAt(path, progress));
  }

  void _drawMarker(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at, 15, Paint()..color = color.withValues(alpha: 0.30));
    canvas.drawCircle(at, 11.5, Paint()..color = color);
    canvas.drawCircle(
      at,
      11.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.train.codePoint),
        style: TextStyle(
          fontSize: 13,
          height: 1,
          fontFamily: Icons.train.fontFamily,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    glyph.layout();
    glyph.paint(canvas, at - Offset(glyph.width / 2, glyph.height / 2));
  }

  static Offset _pointAt(List<Offset> path, double t) {
    if (path.length == 1) return path.first;
    var target = t.clamp(0.0, 1.0);
    final total = _lengthOf(path);
    if (total <= 0) return path.first;
    target *= total;
    for (var i = 1; i < path.length; i++) {
      final d = (path[i] - path[i - 1]).distance;
      if (target <= d) {
        final f = d == 0 ? 0.0 : target / d;
        return Offset.lerp(path[i - 1], path[i], f)!;
      }
      target -= d;
    }
    return path.last;
  }

  static double _lengthOf(List<Offset> path) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += (path[i] - path[i - 1]).distance;
    }
    return total;
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.dotFill != dotFill ||
      old.shapes != shapes ||
      old.stations != stations ||
      old.livePositions != livePositions;
}

// Info

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.data});

  final _TrackData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = data.route;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Color(r.colorValue),
              child: Text(
                r.shortName,
                style: TextStyle(
                  color: Color(r.textColorValue),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.longName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.stations.length} stations · ${r.category}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Live card

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.route,
    required this.repo,
    required this.positions,
    required this.networkCount,
  });

  final TransitRoute route;
  final TransitRepository repo;

  /// Live vehicles already resolved to [route].
  final List<VehiclePosition> positions;

  /// Live vehicles on any line, after resolution.
  final int networkCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final err = repo.liveFetchError;
    final last = repo.lastLiveFetchAt;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cell_tower, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Live vehicles',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (err != null && networkCount == 0)
                  TextButton.icon(
                    onPressed: () => _retry(context, repo),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  )
                else
                  Text(
                    _statusLabel(last),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (positions.isEmpty)
              Text(
                'No live vehicles on this line right now.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: positions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final p = positions[i];
                  final speed = p.speedKmhLabel();
                  return Row(
                    children: [
                      const Icon(Icons.train, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        p.displayName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (p.tripId != null) ...[
                        Text(
                          'trip ${p.tripId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (speed.isNotEmpty)
                        Text(
                          speed,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DateTime? last) {
    if (positions.isNotEmpty) {
      final age = DateTime.now().difference(last ?? DateTime.now());
      if (age > const Duration(minutes: 2)) {
        return 'Possibly stale · ${age.inSeconds}s ago';
      }
      return '${positions.length} on this line · ${age.inSeconds}s ago';
    }
    if (networkCount > 0) {
      return '$networkCount on network, none here';
    }
    if (last == null) return 'Waiting for first update…';
    return 'No vehicles reported';
  }

  static void _retry(BuildContext context, TransitRepository repo) {
    repo.startLivePolling();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retrying live feed…')),
    );
  }
}
