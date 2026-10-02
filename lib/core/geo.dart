import 'dart:math' as math;

/// Geo helpers. Haversine must match the SQL haversine_km used by quote_fare.

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

const LatLng kMatiCenter = LatLng(6.955, 126.2166);

double haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  double toRad(double deg) => deg * math.pi / 180;

  final dLat = toRad(b.lat - a.lat);
  final dLng = toRad(b.lng - a.lng);
  final lat1 = toRad(a.lat);
  final lat2 = toRad(b.lat);

  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);

  return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

/// Rough ETA for a tricycle in city traffic. [VERIFY: average speed in Mati]
int etaMinutes(double distanceKm, {double speedKph = 18}) {
  if (distanceKm <= 0) return 0;
  return math.max(1, ((distanceKm / speedKph) * 60).round());
}
