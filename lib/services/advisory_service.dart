import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/service_status.dart';

/// Loads published service advisories.
///
/// Reads the bundled assets/advisories.json today. To go live later, swap
/// [load] for an http.get of a JSON URL with the same shape.
class AdvisoryService {
  AdvisoryService({this.assetPath = 'assets/advisories.json'});

  final String assetPath;

  Future<List<Advisory>> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['advisories'] : decoded;
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) Advisory.fromJson(e),
      ];
    } catch (_) {
      return const []; // missing or malformed file = no advisories
    }
  }
}