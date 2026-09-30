import 'package:flutter/material.dart';

import 'models/route.dart';
import 'models/station.dart';
import 'repositories/transit_repositories.dart';
import 'services/transit_api.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyTransit',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      home: const StationPage(),
    );
  }
}

class _Data {
  final List<TransitRoute> routes;
  final List<Station> stations;
  _Data(this.routes, this.stations);
}

class StationPage extends StatefulWidget {
  const StationPage({super.key});

  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  final _repo = TransitRepository(TransitApi());
  late final Future<_Data> _future = _load();

  Future<_Data> _load() async =>
      _Data(await _repo.getRoutes(), await _repo.getStations());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MyTransit')),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load: ${snap.error}'));
          }
          final data = snap.data!;
          return ListView(
            children: [
              for (final route in data.routes)
                _RouteSection(
                  route: route,
                  stations: data.stations
                      .where((s) => s.routeId == route.id)
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteSection extends StatelessWidget {
  const _RouteSection({required this.route, required this.stations});
  final TransitRoute route;
  final List<Station> stations;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: Color(route.colorValue),
        child: Text(
          route.shortName,
          style: TextStyle(
            color: Color(route.textColorValue),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(route.longName),
      subtitle: Text('${route.description} · ${stations.length} stations'),
      children: [
        for (final s in stations)
          ListTile(
            dense: true,
            title: Text(s.name),
            subtitle: Text(s.id),
            trailing: s.isAccessible
                ? const Icon(Icons.accessible, size: 18)
                : null,
          ),
      ],
    );
  }
}