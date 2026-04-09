import 'package:latlong2/latlong.dart';

class GpsUtils {
  static const double _radiusInMeters = 15.0;

  static bool istImRadius(double bLat, double bLng, double pLat, double pLng) {
    return berechneDistanz(bLat, bLng, pLat, pLng) <= _radiusInMeters;
  }

  /// Berechnet die Distanz zwischen zwei GPS-Koordinaten in Metern
  static double berechneDistanz(
      double lat1, double lng1, double lat2, double lng2) {
    const Distance distance = Distance();
    return distance.as(
        LengthUnit.Meter, LatLng(lat1, lng1), LatLng(lat2, lng2));
  }

  /// Prüft ob der Benutzer innerhalb des 15m Radius um einen Papierkorb ist

  /// Gibt die Distanz zum Papierkorb zurück
  static double getDistanzZumPapierkorb(double benutzerLat, double benutzerLng,
      double papierkorbLat, double papierkorbLng) {
    return berechneDistanz(
        benutzerLat, benutzerLng, papierkorbLat, papierkorbLng);
  }

  /// Formatiert die Distanz für die Anzeige
  static String formatiereDistanz(double distanzInMetern) {
    if (distanzInMetern < 10) {
      return '${distanzInMetern.toStringAsFixed(1)} m';
    } else {
      return '${distanzInMetern.round()} m';
    }
  }

  /// Konstante für den Radius
  static double get radiusInMeters => _radiusInMeters;
}
