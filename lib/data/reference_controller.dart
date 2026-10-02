import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../models/enums.dart';
import '../models/rows.dart';
import 'api.dart';

/// Fare zones, fare matrix, and platform settings. Loaded once at startup.
class ReferenceController extends ChangeNotifier {
  ReferenceController(this.api);

  final Api api;

  bool loading = true;
  String? error;
  AppSettings settings = const AppSettings();
  List<FareZone> zones = const [];
  List<FareMatrixEntry> matrix = const [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.fetchSettings(),
        api.fetchZones(),
        api.fetchMatrix(),
      ]);
      settings = results[0] as AppSettings;
      zones = results[1] as List<FareZone>;
      matrix = results[2] as List<FareMatrixEntry>;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  FareZone? zoneById(String? id) {
    if (id == null) return null;
    for (final zone in zones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  String zoneName(String? id) => zoneById(id)?.name ?? '—';

  FareZone? nearestZone(LatLng point) {
    FareZone? best;
    var bestKm = double.infinity;
    for (final zone in zones) {
      final km = haversineKm(point, LatLng(zone.centroidLat, zone.centroidLng));
      if (km < bestKm) {
        bestKm = km;
        best = zone;
      }
    }
    return best;
  }

  bool hasMatrixRate(String? originZone, String? destZone, VehicleType type) {
    if (originZone == null || destZone == null) return false;
    return matrix.any((r) =>
        r.isActive &&
        r.originZone == originZone &&
        r.destZone == destZone &&
        r.vehicleType == type);
  }

  /// Instant, local fare preview. Mirrors public.quote_fare; the server value is
  /// authoritative and is what gets stored on the booking.
  double previewFare({
    required VehicleType vehicleType,
    String? originZone,
    String? destZone,
    LatLng? origin,
    LatLng? dest,
    DiscountType? discount,
  }) {
    double? fare;
    if (originZone != null && destZone != null) {
      for (final row in matrix) {
        if (row.isActive &&
            row.originZone == originZone &&
            row.destZone == destZone &&
            row.vehicleType == vehicleType) {
          fare = row.fare;
          break;
        }
      }
    }
    fare ??= settings.baseFare +
        (origin != null && dest != null ? settings.perKmRate * haversineKm(origin, dest) : 0);
    if (discount != null) {
      fare = fare * (1 - settings.discountRate);
    }
    return fare.roundToDouble();
  }
}
