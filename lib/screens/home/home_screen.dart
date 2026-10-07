import 'package:flutter/material.dart';

import '../../models/route.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/transit_api.dart';
import '../../widgets/live_clock.dart';
import '../live_track/live_track_screen.dart';
import '../settings/settings_screen.dart';
import '../train_list/train_list_screen.dart';

/// Landing screen: quick links into the three parts of the app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = TransitRepository(TransitApi());
  late final Future<_Stats> _stats = _load();

  Future<_Stats> _load() async => _Stats(
        await _repo.getRoutes(),
        (await _repo.getStations()).length,
      );

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _NetworkCard(
                future: _stats,
                onOpen: () => _push(TrainListScreen(repo: _repo)),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Stats {
  _Stats(this.routes, this.stationCount);
  final List<TransitRoute> routes;
  final int stationCount;
}

// ───────────────────────── Pieces ─────────────────────────

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
  const _NetworkCard({required this.future, required this.onOpen});

  final Future<_Stats> future;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
          child: FutureBuilder<_Stats>(
            future: future,
            builder: (context, snap) {
              final st = snap.data;
              final loading = snap.connectionState != ConnectionState.done;
              return Row(
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
                          loading
                              ? 'Loading feed…'
                              : snap.hasError
                                  ? 'Feed unavailable'
                                  : '${st!.routes.length} lines · '
                                      '${st.stationCount} stations',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (st != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final r in st.routes.take(6))
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
              );
            },
          ),
        ),
      ),
    );
  }
}
