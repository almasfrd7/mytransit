import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/station.dart';

/// Favourite stations, persisted locally. Falls back to memory-only if
/// storage is unavailable (e.g. in widget tests).
class FavouritesStore extends ChangeNotifier {
  FavouritesStore._();
  static final FavouritesStore instance = FavouritesStore._();

  static const _prefsKey = 'favourite_stations';

  /// A stop id can repeat across lines (KTMB), so key by route + stop.
  static String keyOf(Station s) => '${s.routeId}|${s.id}';

  final List<String> _keys = [];
  List<String> get keys => List.unmodifiable(_keys);

  bool contains(Station s) => _keys.contains(keyOf(s));

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _keys
        ..clear()
        ..addAll(prefs.getStringList(_prefsKey) ?? const []);
      notifyListeners();
    } catch (_) {
      // Storage unavailable; stay in-memory.
    }
  }

  Future<void> toggle(Station s) async {
    final k = keyOf(s);
    if (!_keys.remove(k)) _keys.add(k);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _keys);
    } catch (_) {}
  }
}