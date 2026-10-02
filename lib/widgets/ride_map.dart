import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../core/geo.dart';
import '../core/theme.dart';

enum MapMarkerKind { driver, pickup, dropoff, sos }

class RideMarker {
  const RideMarker({
    required this.id,
    required this.point,
    required this.label,
    this.kind = MapMarkerKind.driver,
  });

  final String id;
  final LatLng point;
  final String label;
  final MapMarkerKind kind;
}

Color _colorFor(MapMarkerKind kind) => switch (kind) {
      MapMarkerKind.driver => AppTheme.brand700,
      MapMarkerKind.pickup => AppTheme.brand600,
      MapMarkerKind.dropoff => const Color(0xFF65A30D),
      MapMarkerKind.sos => AppTheme.sos500,
    };

class RideMap extends StatelessWidget {
  const RideMap({
    super.key,
    required this.markers,
    this.center,
    this.zoom = 14,
    this.height = 220,
  });

  final List<RideMarker> markers;
  final LatLng? center;
  final double zoom;
  final double height;

  @override
  Widget build(BuildContext context) {
    final initial = center ??
        (markers.isNotEmpty ? markers.first.point : kMatiCenter);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: ll.LatLng(initial.lat, initial.lng),
            initialZoom: zoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sakayta.sakay_ta',
            ),
            MarkerLayer(
              markers: [
                for (final marker in markers)
                  Marker(
                    point: ll.LatLng(marker.point.lat, marker.point.lng),
                    width: 30,
                    height: 30,
                    child: Tooltip(
                      message: marker.label,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _colorFor(marker.kind),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
