import 'package:flutter/material.dart';

import '../../models/arrival.dart';
import '../../models/route.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/favourites_store.dart';
import '../../services/location_api.dart';
import '../../services/transit_api.dart';
import '../../widgets/live_clock.dart';
import '../../widgets/station_card.dart';
import '../live_track/live_track_screen.dart';
import '../settings/settings_screen.dart';
import '../station/station_detail_screen.dart';
import '../train_list/train_list_screen.dart';

/// Landing screen: quick links, favourites and nearby stations.
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

  _NearbyState _nearbyState = _NearbyState.idle;
  List<_Nearby> _nearby = const [];
  String? _nearbyError;

  Future<_HomeData> _load() async =>
      _HomeData(await _repo.getRoutes(), await _repo.getStations());

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

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
    } catch (e) {
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

  static String _distance(double m) =>
      m < 1000 ? '${m.round()} m away' : '${(m / 1000).toStringAsFixed(1)} km away';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('MyTransit')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                _greeting,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LiveClock(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _SectionLabel('Explore'),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _HeroTile(
                icon: Icons.train_rounded,
                title: 'Train list',
                subtitle: 'Every station, line and schedule',
                color: cs.primaryContainer,
                onColor: cs.onPrimaryContainer,
                onTap: () => _push(TrainListScreen(repo: _repo)),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _NavTile(
                      icon: Icons.satellite_alt_rounded,
                      title: 'Live track',
                      subtitle: 'Follow trains on the line',
                      color: cs.tertiaryContainer,
                      onColor: cs.onTertiaryContainer,
                      onTap: () => _push(LiveTrackScreen(repo: _repo)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NavTile(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      subtitle: 'Appearance and app info',
                      color: cs.secondaryContainer,
                      onColor: cs.onSecondaryContainer,
                      onTap: () => _push(const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<_HomeData>(
              future: _data,
              builder: (context, snap) {
                final d = snap.data;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d != null) _favourites(d),
                      if (d != null) _nearbySection(d),
                      const SizedBox(height: 16),
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
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
            const SizedBox(height: 16),
            const _SectionLabel('Favourites'),
            const SizedBox(height: 8),
            for (final s in stations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
        body = Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: cs.surfaceContainerLow,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.only(bottom: 6),
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
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: _SectionLabel('Nearby stations')),
            if (_nearbyState == _NearbyState.ready)
              IconButton(
                tooltip: 'Refresh location',
                icon: const Icon(Icons.refresh),
                onPressed: _findNearby,
              ),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

// ───────────────────────── Pieces ─────────────────────────

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
        String text = '';
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
              ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: onColor.withValues(alpha: 0.15),
                child: Icon(icon, color: onColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: onColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: onColor.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: onColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: onColor, size: 26),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  color: onColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onColor.withValues(alpha: 0.8),
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.alt_route_rounded, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Klang Valley + KTMB rail network',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failed
                          ? 'Feed unavailable'
                          : d == null
                          ? 'Loading feed…'
                          : '${d.routes.length} lines · '
                          '${d.stations.length} stations',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (d != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final r in d.routes.take(6))
                        CircleAvatar(
                          radius: 5,
                          backgroundColor: Color(r.colorValue),
                        ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}