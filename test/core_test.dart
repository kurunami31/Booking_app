import 'package:flutter_test/flutter_test.dart';

import 'package:sakay_ta/core/format.dart';
import 'package:sakay_ta/core/geo.dart';

void main() {
  group('haversineKm', () {
    test('is zero for the same point', () {
      expect(haversineKm(kMatiCenter, kMatiCenter), closeTo(0, 0.00001));
    });

    test('is symmetric', () {
      const a = LatLng(6.955, 126.2166);
      const b = LatLng(6.942, 126.268);
      expect(haversineKm(a, b), closeTo(haversineKm(b, a), 0.000001));
    });

    test('matches one degree of latitude', () {
      expect(haversineKm(const LatLng(0, 0), const LatLng(1, 0)),
          closeTo(111.19, 0.1));
    });
  });

  group('etaMinutes', () {
    test('never returns less than one minute for a positive distance', () {
      expect(etaMinutes(0.01), 1);
    });

    test('returns zero for no distance', () {
      expect(etaMinutes(0), 0);
    });
  });

  group('formatPeso', () {
    test('formats whole pesos', () {
      expect(formatPeso(15), 'PHP 15');
      expect(formatPeso(1250), 'PHP 1,250');
    });

    test('shows cents when present', () {
      expect(formatPeso(13.5), 'PHP 13.50');
    });
  });

  group('formatDistanceKm', () {
    test('uses metres below one kilometre', () {
      expect(formatDistanceKm(0.4), '400 m');
    });

    test('uses kilometres above one', () {
      expect(formatDistanceKm(2.35), '2.4 km');
    });
  });
}
