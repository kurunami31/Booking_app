import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/presence_service.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ui.dart';
import 'driver_onboarding.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  String? _error;
  String? _acceptingId;

  @override
  void initState() {
    super.initState();
    // If the driver was online when the app last closed, resume sharing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final presence = context.read<PresenceService>();
      final driver = context.read<AuthController>().driver;
      if (driver?.isOnline == true && !presence.isOnline) {
        presence.goOnline();
      }
    });
  }

  Future<void> _toggleOnline(bool next) async {
    final auth = context.read<AuthController>();
    final presence = context.read<PresenceService>();
    if (next) {
      await presence.goOnline();
    } else {
      await presence.goOffline();
    }
    await auth.refresh();
  }

  Future<void> _accept(String bookingId) async {
    final api = context.read<Api>();
    setState(() {
      _acceptingId = bookingId;
      _error = null;
    });
    try {
      await api.acceptBooking(bookingId);
      if (mounted) context.go('/driver/trip');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final presence = context.watch<PresenceService>();
    final driver = auth.driver;

    if (auth.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (driver == null) return const DriverOnboardingForm();
    if (driver.status == DriverStatus.suspended) return const DriverSuspendedView();
    if (driver.status == DriverStatus.pending) return const DriverPendingView();

    final vehicle = auth.vehicle;
    if (vehicle == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          title: 'No vehicle on record',
          description: 'Contact the LGU desk to link a vehicle to your account.',
        ),
      );
    }

    final api = context.read<Api>();
    final position = presence.lastPosition;
    final online = presence.isOnline;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Driver dashboard',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(
                    '${auth.profile?.fullName ?? ''} · ${vehicle.type.label}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            StatusPill(online ? 'Online' : 'Offline',
                tone: online ? Tone.good : Tone.muted),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        if (presence.error != null) ...[
          ErrorBanner(presence.error!, tone: Tone.warn),
          const SizedBox(height: 12),
        ],
        InfoCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Go online',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text(
                      'Stop doing tuyok-tuyok. The app sends ride requests to you.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    if (position != null)
                      Text(
                        'Sharing location ${position.lat.toStringAsFixed(4)}, ${position.lng.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    const Text(
                      'Location is shared in the background while you are online.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: online,
                onChanged: _toggleOnline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Ride requests'),
        if (!online)
          const EmptyState(
            title: 'You are offline',
            description: 'Go online to receive ride requests.',
          )
        else
          StreamBuilder(
            stream: api.openRequests(vehicle.type),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? const <Booking>[];
              if (requests.isEmpty) {
                return const EmptyState(
                  title: 'No requests right now',
                  description:
                      'Stay online. Requests for your vehicle type will show up here.',
                );
              }
              return Column(
                children: [
                  for (final request in requests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RequestCard(
                        request: request,
                        position: position,
                        accepting: _acceptingId == request.id,
                        onAccept: () => _accept(request.id),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 12),
        InfoCard(
          child: Text(
            'Your unit: ${vehicle.type.label} · Unit ${vehicle.unitNo ?? '—'} · Plate ${vehicle.plateNo ?? '—'}\n'
            'Completed ${driver.completedCount} · Cancelled ${driver.cancelledCount}'
            '${driver.rating != null ? ' · Rating ${driver.rating!.toStringAsFixed(1)} (${driver.ratingCount})' : ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.position,
    required this.accepting,
    required this.onAccept,
  });

  final Booking request;
  final LatLng? position;
  final bool accepting;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final pickup = request.originLat != null && request.originLng != null
        ? LatLng(request.originLat!, request.originLng!)
        : null;
    final distance = (position != null && pickup != null)
        ? haversineKm(position!, pickup)
        : null;

    return InfoCard(
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
                    Text(
                      '${request.originLabel ?? 'Pickup'} → ${request.destLabel ?? 'Dropoff'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Requested ${formatRelative(request.requestedAt)} · ${shortId(request.id)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    Text(
                      distance != null
                          ? '~${formatDistanceKm(distance)} away · about ${etaMinutes(distance)} min'
                          : 'Distance unknown — location off',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Text(formatPeso(request.fare),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: accepting ? null : onAccept,
            child: accepting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Accept this ride'),
          ),
        ],
      ),
    );
  }
}
