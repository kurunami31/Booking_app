import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/ui.dart';

class AdminSosPage extends StatefulWidget {
  const AdminSosPage({super.key});

  @override
  State<AdminSosPage> createState() => _AdminSosPageState();
}

class _AdminSosPageState extends State<AdminSosPage> {
  String? _busyId;
  String? _error;

  Future<void> _update(SosAlert alert, SosStatus status) async {
    setState(() {
      _busyId = alert.id;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{'status': status.db};
      if (status == SosStatus.acknowledged) {
        patch['acknowledged_at'] = DateTime.now().toUtc().toIso8601String();
      }
      if (status == SosStatus.closedFalseAlarm ||
          status == SosStatus.closedResolved) {
        patch['closed_at'] = DateTime.now().toUtc().toIso8601String();
      }
      await Supabase.instance.client
          .from('sos_alerts')
          .update(patch)
          .eq('id', alert.id);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();

    return StreamBuilder<List<SosAlert>>(
      stream: api.sosAlerts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final alerts = snapshot.data!
          ..sort((a, b) =>
              (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        final open = alerts.where((a) => a.status == SosStatus.open).toList();

        final markers = <RideMarker>[
          for (final a in alerts)
            if (a.lat != null &&
                a.lng != null &&
                a.status != SosStatus.closedFalseAlarm &&
                a.status != SosStatus.closedResolved)
              RideMarker(
                id: a.id,
                point: LatLng(a.lat!, a.lng!),
                label: 'SOS ${shortId(a.id)}',
                kind: MapMarkerKind.sos,
              ),
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Emergency response',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text('SOS alerts raised by passengers and drivers.',
                style: TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 12),
            const ErrorBanner(
              'Who actually receives this alert and the response protocol must be confirmed with PNP Mati, MDRRMO, and 911 before a pilot. The app logs the alert; it does not guarantee a response time. [VERIFY]',
              tone: Tone.warn,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              ErrorBanner(_error!),
              const SizedBox(height: 12),
            ],
            if (markers.isNotEmpty) ...[
              RideMap(markers: markers, zoom: 13),
              const SizedBox(height: 12),
            ],
            if (open.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ErrorBanner(
                  '${open.length} open alert${open.length > 1 ? 's' : ''} need action',
                  tone: Tone.bad,
                ),
              ),
            if (alerts.isEmpty)
              const EmptyState(
                title: 'No SOS alerts',
                description: 'Alerts raised during trips appear here.',
              )
            else
              for (final alert in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SOS ${shortId(alert.id)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                    '${formatDateTime(alert.createdAt)} · ${formatRelative(alert.createdAt)}'
                                    '${alert.bookingId != null ? ' · trip ${shortId(alert.bookingId!)}' : ''}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                  Text(
                                    alert.lat != null && alert.lng != null
                                        ? 'Location ${alert.lat!.toStringAsFixed(4)}, ${alert.lng!.toStringAsFixed(4)}'
                                        : 'No location captured — likely a signal dead zone',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              alert.status.label,
                              tone: alert.status == SosStatus.open
                                  ? Tone.bad
                                  : alert.status == SosStatus.acknowledged
                                      ? Tone.warn
                                      : Tone.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (alert.status == SosStatus.open)
                          FilledButton(
                            onPressed: _busyId == alert.id
                                ? null
                                : () => _update(alert, SosStatus.acknowledged),
                            child: const Text('Acknowledge'),
                          ),
                        if (alert.status == SosStatus.acknowledged)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busyId == alert.id
                                      ? null
                                      : () => _update(alert, SosStatus.closedResolved),
                                  child: const Text('Close — resolved'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busyId == alert.id
                                      ? null
                                      : () =>
                                          _update(alert, SosStatus.closedFalseAlarm),
                                  child: const Text('False alarm'),
                                ),
                              ),
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
  }
}
