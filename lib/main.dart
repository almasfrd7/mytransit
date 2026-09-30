import 'package:flutter/material.dart';

import 'models/station.dart';
import 'services/transit_api.dart';

void main() {
  runApp(const MyTransitApp());
}

class MyTransitApp extends StatelessWidget {
  const MyTransitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyTransit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const StationPage(),
    );
  }
}

class StationPage extends StatefulWidget {
  const StationPage({super.key});

  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  final TransitService transitService = TransitService();

  late Future<List<Station>> stationsFuture;

  @override
  void initState() {
    super.initState();

    stationsFuture = transitService.fetchStations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyTransit'),
      ),
      body: FutureBuilder<List<Station>>(
        future: stationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final stations = snapshot.data ?? [];

          if (stations.isEmpty) {
            return const Center(
              child: Text('No stations found.'),
            );
          }

          return ListView.builder(
            itemCount: stations.length,
            itemBuilder: (context, index) {
              final station = stations[index];

              return ListTile(
                leading: const Icon(Icons.train),
                title: Text(station.name),
                subtitle: Text(
                  '${station.latitude}, ${station.longitude}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}