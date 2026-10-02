import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ui.dart';

class DriverEarningsPage extends StatelessWidget {
  const DriverEarningsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final driverId = context.watch<AuthController>().driver?.id ?? '';

    return StreamBuilder(
      stream: api.bookingsForDriver(driverId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final completed = snapshot.data!
            .where((b) => b.status == BookingStatus.completed)
            .toList()
          ..sort((a, b) => (b.completedAt ?? DateTime(0))
              .compareTo(a.completedAt ?? DateTime(0)));

        if (completed.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: EmptyState(
              title: 'No completed trips yet',
              description: 'Finish a trip to see earnings here.',
            ),
          );
        }

        return FutureBuilder<List<Payment>>(
          future: api.fetchPaymentsForBookings(completed.map((b) => b.id).toList()),
          builder: (context, paymentSnapshot) {
            final payments = paymentSnapshot.data ?? const <Payment>[];
            final byBooking = {for (final p in payments) p.bookingId: p};

            var gross = 0.0;
            var commission = 0.0;
            var net = 0.0;
            for (final b in completed) {
              final p = byBooking[b.id];
              if (p == null) continue;
              gross += p.amount;
              commission += p.commission;
              net += p.driverNet;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Earnings',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const Text('Completed trips and your net after commission.',
                    style: TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: StatTile(label: 'Trips', value: '${completed.length}')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'Net pay',
                        value: formatPeso(net),
                        hint: 'After commission',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: StatTile(label: 'Gross fares', value: formatPeso(gross))),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                          StatTile(label: 'Commission', value: formatPeso(commission)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionTitle('Trips'),
                for (final b in completed)
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
                                  '${formatDateTime(b.completedAt)} · ${shortId(b.id)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatPeso(byBooking[b.id]?.driverNet ?? b.fare),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              StatusPill(
                                byBooking[b.id]?.status.label ?? 'no payment',
                                tone: byBooking[b.id]?.status == PaymentStatus.collected
                                    ? Tone.good
                                    : Tone.warn,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text(
                  'Settlement is manual in this MVP. Commission is recorded per trip; the office settles payouts separately. [VERIFY settlement cycle with the operator]',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
