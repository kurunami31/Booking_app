import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';

class PassengerHistoryPage extends StatelessWidget {
  const PassengerHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final userId = context.watch<AuthController>().userId ?? '';

    return StreamBuilder(
      stream: api.bookingsForPassenger(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final bookings = snapshot.data!
          ..sort((a, b) => (b.requestedAt ?? DateTime(0))
              .compareTo(a.requestedAt ?? DateTime(0)));

        if (bookings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: EmptyState(
              title: 'No rides yet',
              description: 'Your booked trips will appear here.',
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final b = bookings[index];
            return InfoCard(
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
                          '${formatDateTime(b.requestedAt)} · ${b.vehicleType.label} · ${shortId(b.id)}',
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
                      StatusPill(b.status.label, tone: _tone(b.status)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

Tone _tone(BookingStatus status) => switch (status) {
      BookingStatus.completed => Tone.good,
      BookingStatus.cancelled => Tone.muted,
      BookingStatus.noShow => Tone.bad,
      BookingStatus.requested => Tone.warn,
      _ => Tone.info,
    };
