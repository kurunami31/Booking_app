import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/api.dart';
import '../../models/rows.dart';
import '../../widgets/ui.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  late Future<_ReportData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportData> _load() async {
    final api = context.read<Api>();
    final bookings = await api.fetchCompletedBookings();
    final payments = await api.fetchPaymentsForBookings(
      bookings.map((b) => b.id).toList(),
    );
    return _ReportData(
      bookings: bookings,
      payments: {for (final p in payments) p.bookingId: p},
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        var fares = 0.0;
        var commission = 0.0;
        for (final b in data.bookings) {
          fares += b.fare;
          commission += data.payments[b.id]?.commission ?? 0;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Trip reports',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text('Completed trips for LGU review and operator settlement.',
                style: TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: StatTile(label: 'Trips', value: '${data.bookings.length}')),
                const SizedBox(width: 8),
                Expanded(
                    child: StatTile(label: 'Gross fares', value: formatPeso(fares))),
                const SizedBox(width: 8),
                Expanded(
                    child: StatTile(label: 'Commission', value: formatPeso(commission))),
              ],
            ),
            const SizedBox(height: 16),
            if (data.bookings.isEmpty)
              const EmptyState(title: 'No completed trips yet')
            else
              for (final b in data.bookings)
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
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${formatDateTime(b.completedAt)} · ${shortId(b.id)} · ${b.vehicleType.label}',
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
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            StatusPill(
                              data.payments[b.id]?.status.label ?? 'no payment',
                              tone: Tone.warn,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            const Text(
              'CSV export is available in the web admin. This report view is read-only. [VERIFY reporting requirements with the LGU]',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        );
      },
    );
  }
}

class _ReportData {
  const _ReportData({required this.bookings, required this.payments});
  final List<Booking> bookings;
  final Map<String, Payment> payments;
}
