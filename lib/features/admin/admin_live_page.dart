import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../models/rows.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/ui.dart';

class AdminLivePage extends StatelessWidget {
  const AdminLivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();

    return StreamBuilder<List<Booking>>(
      stream: api.allActiveBookings(),
      builder: (context, bookingSnapshot) {
        return StreamBuilder<List<Driver>>(
          stream: api.onlineDrivers(),
          builder: (context, driverSnapshot) {
            return StreamBuilder<List<SosAlert>>(
              stream: api.sosAlerts(),
              builder: (context, sosSnapshot) {
                final bookings = bookingSnapshot.data ?? const <Booking>[];
                final drivers = driverSnapshot.data ?? const <Driver>[];
                final openSos = (sosSnapshot.data ?? const <SosAlert>[])
                    .where((s) => s.status.db == 'open')
                    .toList();

                final markers = <RideMarker>[
                  for (final b in bookings)
                    if (b.originLat != null && b.originLng != null)
                      RideMarker(
                        id: 'o-${b.id}',
                        point: LatLng(b.originLat!, b.originLng!),
                        label: 'Pickup ${shortId(b.id)}',
                        kind: MapMarkerKind.pickup,
                      ),
                  for (final b in bookings)
                    if (b.destLat != null && b.destLng != null)
                      RideMarker(
                        id: 'd-${b.id}',
                        point: LatLng(b.destLat!, b.destLng!),
                        label: 'Dropoff ${shortId(b.id)}',
                        kind: MapMarkerKind.dropoff,
                      ),
                  for (final d in drivers)
                    if (d.lastLat != null && d.lastLng != null)
                      RideMarker(
                        id: 'drv-${d.id}',
                        point: LatLng(d.lastLat!, d.lastLng!),
                        label: 'Driver ${shortId(d.id)}',
                        kind: MapMarkerKind.driver,
                      ),
                  for (final s in openSos)
                    if (s.lat != null && s.lng != null)
                      RideMarker(
                        id: 'sos-${s.id}',
                        point: LatLng(s.lat!, s.lng!),
                        label: 'SOS ${shortId(s.id)}',
                        kind: MapMarkerKind.sos,
                      ),
                ];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Live operations',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Text('Active trips, online drivers, and open SOS alerts.',
                        style: TextStyle(color: Color(0xFF64748B))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: StatTile(
                                label: 'Active trips', value: '${bookings.length}')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: StatTile(
                                label: 'Drivers online', value: '${drivers.length}')),
                        const SizedBox(width: 8),
                        Expanded(
                            child:
                                StatTile(label: 'Open SOS', value: '${openSos.length}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (openSos.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ErrorBanner(
                          'Open SOS alerts need action. Go to the SOS tab.',
                          tone: Tone.bad,
                        ),
                      ),
                    if (markers.isNotEmpty) RideMap(markers: markers, zoom: 13),
                    const SizedBox(height: 16),
                    const SectionTitle('Active trips'),
                    if (bookings.isEmpty)
                      const EmptyState(title: 'No active trips')
                    else
                      for (final b in bookings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InfoCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${b.originLabel ?? 'Pickup'} → ${b.destLabel ?? 'Dropoff'}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        '${shortId(b.id)} · ${b.vehicleType.label} · ${formatRelative(b.requestedAt)}'
                                        '${b.driverId == null ? ' · unassigned' : ''}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(formatPeso(b.fare),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    StatusPill(b.status.label, tone: Tone.info),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
