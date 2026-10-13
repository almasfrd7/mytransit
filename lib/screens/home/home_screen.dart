import 'package:flutter/material.dart';

import '../../models/arrival.dart';
import '../../models/route.dart';
import '../../models/service_status.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/favourites_store.dart';
import '../../services/location_api.dart';
import '../../services/transit_api.dart';
import '../../theme.dart';
import '../../widgets/live_clock.dart';
import '../../widgets/station_card.dart';
import '../../widgets/ui.dart';
import '../live_track/live_track_screen.dart';
import '../service_status/service_status_screen.dart';
import '../settings/settings_screen.dart';
import '../station/station_detail_screen.dart';
import '../train_list/train_list_screen.dart';

/// Landing screen: status banner, quick links, favourites and nearby.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NearbyState { idle, loading, ready, error }

class _Nearby {
  const _Nearby(this.station, this.meters);
  final Station station;
  final double meters;
}

class _HomeData {
  _HomeData(this.routes, this.stations);
  final List<TransitRoute> routes;
  final List<Station> stations;

  late final Map<String, TransitRoute> routesById = {
    for (final r in routes) r.id: r,
  };

  late final Map<String, Station> byKey = {
    for (final s in stations) FavouritesStore.keyOf(s): s,
  };

  List<Station> interchangesOf(Station s) => stations
      .where((o) =>
  o.id != s.id && o.name.toUpperCase() == s.name.toUpperCase())
      .toList();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = TransitRepository(TransitApi());
  final _location = LocationApi();
  late final Future<_HomeData> _data = _load();
  late Future<List<ServiceStatus>> _statuses = _repo.getServiceStatuses();

  _NearbyState _nearbyState = _NearbyState.idle;
  List<_Nearby> _nearby = const [];
  String? _nearbyError;

  Future<_HomeData> _load() async =>
      _HomeData(await _repo.getRoutes(), await _repo.getStations());

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _openStatus() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceStatusScreen(repo: _repo),
    ));
    if (mounted) setState(() => _statuses = _repo.getServiceStatuses());
  }

  void _openStation(_HomeData d, Station s) {
    _push(StationDetailScreen(
      station: s,
      route: d.routesById[s.routeId],
      interchanges: d.interchangesOf(s),
      routesById: d.routesById,
      repo: _repo,
      onOpenStation: (o) => _openStation(d, o),
    ));
  }

  Future<void> _findNearby() async {
    setState(() {
      _nearbyState = _NearbyState.loading;
      _nearbyError = null;
    });
    try {
      final data = await _data;
      final pos = await _location.currentPosition();

      // One row per station name (interchanges collapse to the nearest).
      final best = <String, _Nearby>{};
      for (final s in data.stations) {
        final m = LocationApi.distance(
            pos.latitude, pos.longitude, s.lat, s.lng);
        final k = s.name.trim().toUpperCase();
        final cur = best[k];
        if (cur == null || m < cur.meters) best[k] = _Nearby(s, m);
      }
      final list = best.values.toList()
        ..sort((a, b) => a.meters.compareTo(b.meters));

      if (!mounted) return;
      setState(() {
        _nearby = list.take(5).toList();
        _nearbyState = _NearbyState.ready;
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _nearbyError = e.message;
        _nearbyState = _NearbyState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearbyError = 'Could not get your location.';
        _nearbyState = _NearbyState.error;
      });
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _distance(double m) => m < 1000
      ? '${m.round()} m away'
      : '${(m / 1000).toStringAsFixed(1)} km away';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _actions(),
            ),
            FutureBuilder<_HomeData>(
              future: _data,
              builder: (context, snap) {
                final d = snap.data;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d != null) _favourites(d),
                      if (d != null) _nearbySection(d),
                      const SizedBox(height: 20),
                      _NetworkCard(
                        data: d,
                        failed: snap.hasError,
                        onOpen: () => _push(TrainListScreen(repo: _repo)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero ──

  Widget _hero() {
    return GradientHeader(
      bottomRadius: 36,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'MyTransit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.train_rounded,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_greeting,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const LiveClock(onGradient: true),
          const SizedBox(height: 20),
          _StatusBanner(future: _statuses, onTap: _openStatus),
        ],
      ),
    );
  }

  // ── Quick actions ──

  Widget _actions() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.train_rounded,
              title: 'Train list',
              subtitle: 'Stations and timetables',
              colors: const [Brand.indigo, Brand.violet],
              onTap: () => _push(TrainListScreen(repo: _repo)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: Icons.satellite_alt_rounded,
              title: 'Live track',
              subtitle: 'Trains on the map',
              colors: const [Brand.teal, Brand.mint],
              onTap: () => _push(LiveTrackScreen(repo: _repo)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: Icons.tune_rounded,
              title: 'Settings',
              subtitle: 'Theme and app info',
              colors: const [Brand.amber, Brand.orange],
              onTap: () => _push(const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ── Favourites ──

  Widget _favourites(_HomeData d) {
    return ListenableBuilder(
      listenable: FavouritesStore.instance,
      builder: (context, _) {
        final stations = [
          for (final k in FavouritesStore.instance.keys)
            if (d.byKey[k] != null) d.byKey[k]!,
        ];
        if (stations.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const SectionHeader('Favourites'),
            const SizedBox(height: 10),
            for (final s in stations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StationCard(
                  station: s,
                  route: d.routesById[s.routeId],
                  subtitle: d.routesById[s.routeId]?.longName,
                  trailing: _NextMinutes(repo: _repo, station: s),
                  onTap: () => _openStation(d, s),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Nearby ──

  Widget _nearbySection(_HomeData d) {
    final cs = Theme.of(context).colorScheme;

    Widget body;
    switch (_nearbyState) {
      case _NearbyState.idle:
      case _NearbyState.error:
        body = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_nearbyError != null) ...[
                Text(_nearbyError!, style: TextStyle(color: cs.error)),
                const SizedBox(height: 10),
              ],
              FilledButton.tonalIcon(
                onPressed: _findNearby,
                icon: const Icon(Icons.my_location),
                label: const Text('Find stations near me'),
              ),
            ],
          ),
        );
      case _NearbyState.loading:
        body = const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _NearbyState.ready:
        body = Column(
          children: [
            for (final n in _nearby)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StationCard(
                  station: n.station,
                  route: d.routesById[n.station.routeId],
                  subtitle: _distance(n.meters),
                  onTap: () => _openStation(d, n.station),
                ),
              ),
          ],
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        SectionHeader(
          'Nearby stations',
          trailing: _nearbyState == _NearbyState.ready
              ? IconButton(
            tooltip: 'Refresh location',
            icon: const Icon(Icons.refresh),
            onPressed: _findNearby,
          )
              : null,
        ),
        const SizedBox(height: 10),
        body,
      ],
    );
  }
}

// ───────────────────────── Pieces ─────────────────────────

/// Frosted network-wide status strip that opens the status screen.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.future, required this.onTap});
  final Future<List<ServiceStatus>> future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceStatus>>(
      future: future,
      builder: (context, snap) {
        String title;
        String? sub;
        IconData icon;
        Color iconColor;

        if (snap.hasError) {
          title = 'Service status unavailable';
          sub = 'Tap to retry';
          icon = Icons.cloud_off_rounded;
          iconColor = Colors.white;
        } else if (!snap.hasData) {
          title = 'Checking service…';
          sub = null;
          icon = Icons.hourglass_top_rounded;
          iconColor = Colors.white;
        } else {
          final s = NetworkSummary(snap.data!);
          title = s.headline;
          sub = s.subline;
          icon = s.hasAdvisory
              ? Icons.warning_amber_rounded
              : s.active == 0
              ? Icons.bedtime_rounded
              : Icons.check_circle_rounded;
          iconColor = s.hasAdvisory
              ? const Color(0xFFFFD166)
              : s.active == 0
              ? Colors.white
              : const Color(0xFF86EFAC);
        }

        return Material(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        if (sub != null)
                          Text(sub,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
              const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5, height: 1.25, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _NextMinutes extends StatelessWidget {
  const _NextMinutes({required this.repo, required this.station});
  final TransitRepository repo;
  final Station station;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Arrival>>(
      future: repo.getNextArrivals(station.id,
          routeId: station.routeId, limit: 1),
      builder: (context, snap) {
        final cs = Theme.of(context).colorScheme;
        var text = '';
        if (snap.connectionState == ConnectionState.done) {
          final a = snap.data?.firstOrNull;
          if (a == null) {
            text = '—';
          } else {
            final n = DateTime.now();
            final now =
            Duration(hours: n.hour, minutes: n.minute, seconds: n.second);
            final m = (a.time - now).inMinutes;
            text = m <= 0 ? 'Now' : '$m min';
          }
        }
        return Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
        );
      },
    );
  }
}

/// Feed summary: how many lines and stations the app knows about.
class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.data,
    required this.failed,
    required this.onOpen,
  });

  final _HomeData? data;
  final bool failed;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = data;

    return AppCard(
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.alt_route_rounded, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Klang Valley + KTMB rail network',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? 'Feed unavailable'
                      : d == null
                      ? 'Loading feed…'
                      : '${d.routes.length} lines · '
                      '${d.stations.length} stations',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (d != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 44,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final r in d.routes.take(8))
                      CircleAvatar(
                        radius: 5,
                        backgroundColor: Color(r.colorValue),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.outline),
        ],
      ),
    );
  }
}