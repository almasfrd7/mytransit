import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin wrapper around geolocator: permission flow + one-shot position.
class LocationApi {
  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Location services are turned off.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
          'Location permission is blocked. Enable it in system settings.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Straight-line distance in metres.
  static double distance(
      double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
}