import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/offline_queue.dart';
import '../../data/reference_controller.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/ui.dart';

class PassengerTripPage extends StatelessWidget {
  const PassengerTripPage({super.key});

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
          ..sort((a, b) =>
              (b.requestedAt ?? DateTime(0)).compareTo(a.requestedAt ?? DateTime(0)));
        final active = bookings.where((b) => b.status.isActive).toList();
        final booking = active.isNotEmpty
            ? active.first
            : (bookings.isNotEmpty ? bookings.first : null);

        if (booking == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EmptyState(
                  title: 'No active ride',
                  description: 'Book a tricycle or tuk-tuk/bao-bao to get started.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Book a ride'),
                ),
              ],
            ),
          );
        }

        return _TripBody(booking: booking);
      },
    );
  }
}

class _TripBody extends StatefulWidget {
  const _TripBody({required this.booking});
  final Booking booking;

  @override
  State<_TripBody> createState() => _TripBodyState();
}

class _TripBodyState extends State<_TripBody> {
  bool _busy = false;
  String? _message;
  int _stars = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final api = context.read<Api>();
    final offline = context.read<OfflineQueue>();
    final note = await _askCancelReason();
    if (note == null) return;
    setState(() => _busy = true);
    try {
      await api.transition(widget.booking.id, BookingStatus.cancelled, note: note);
    } catch (_) {
      await offline.addTransition(widget.booking.id, BookingStatus.cancelled, note);
      if (mounted) {
        setState(() => _message =
            'No connection. The cancellation is saved and will send when signal returns.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCancelReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel ride'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Example: nauna na akong nakasakay, nagbago ang plano…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep ride'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBE123C)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSos() async {
    final api = context.read<Api>();
    final offline = context.read<OfflineQueue>();
    final userId = context.read<AuthController>().userId;
    if (userId == null) return;
    LatLng? at;
    try {
      final position = await Geolocator.getCurrentPosition();
      at = LatLng(position.latitude, position.longitude);
    } catch (_) {
      at = null;
    }
    try {
      await api.insertSos(
        bookingId: widget.booking.id,
        triggeredBy: userId,
        at: at,
      );
    } catch (_) {
      await offline.addSos(
            bookingId: widget.booking.id,
            triggeredBy: userId,
            at: at,
          );
    }
  }

  Future<void> _rate() async {
    final api = context.read<Api>();
    final userId = context.read<AuthController>().userId;
    if (userId == null) return;
    setState(() => _busy = true);
    try {
      await api.insertRating(
        bookingId: widget.booking.id,
        raterRole: UserRole.passenger,
        raterId: userId,
        stars: _stars,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (mounted) setState(() => _message = 'Thanks. Your rating was recorded.');
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == '23505' ? 'Already rated.' : e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save the rating.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final reference = context.read<ReferenceController>();
    final api = context.read<Api>();
    final canSos = {
      BookingStatus.assigned,
      BookingStatus.arrived,
      BookingStatus.inProgress,
    }.contains(booking.status);

    final markers = <RideMarker>[
      if (booking.originLat != null && booking.originLng != null)
        RideMarker(
          id: 'origin',
          point: LatLng(booking.originLat!, booking.originLng!),
          label: 'Pickup: ${booking.originLabel ?? ''}',
          kind: MapMarkerKind.pickup,
        ),
      if (booking.destLat != null && booking.destLng != null)
        RideMarker(
          id: 'dest',
          point: LatLng(booking.destLat!, booking.destLng!),
          label: 'Dropoff: ${booking.destLabel ?? ''}',
          kind: MapMarkerKind.dropoff,
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.status.label,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(
                    'Trip ${shortId(booking.id)} · ${booking.vehicleType.label}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            _toneFor(booking.status) != null
                ? StatusPill(booking.status.name, tone: _toneFor(booking.status)!)
                : const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 12),
        if (_message != null) ...[
          ErrorBanner(_message!, tone: Tone.warn),
          const SizedBox(height: 12),
        ],
        if (markers.isNotEmpty) ...[
          RideMap(markers: markers, center: markers.first.point),
          const SizedBox(height: 12),
        ],
        if (booking.status.isActive)
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Fixed fare',
                        style: TextStyle(color: Color(0xFF64748B))),
                    Text(formatPeso(booking.fare),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                  ],
                ),
                Text(
                  '${booking.distanceKm != null ? '${formatDistanceKm(booking.distanceKm)} · ' : ''}'
                  '${booking.passengerCount} passenger${booking.passengerCount > 1 ? 's' : ''}'
                  '${booking.hasLuggage ? ' · with luggage' : ''}'
                  '${booking.discountType != null ? ' · ${booking.discountType!.label} discount' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                Text(
                  '${reference.zoneName(booking.originZone)} → ${reference.zoneName(booking.destZone)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        if (booking.driverId != null) ...[
          const SizedBox(height: 12),
          FutureBuilder<List<dynamic>>(
            future: Future.wait([
              api.fetchDriverById(booking.driverId!),
              api.fetchBooking(booking.id),
            ]),
            builder: (context, snapshot) {
              final driver = snapshot.data?[0] as Driver?;
              if (driver == null) return const SizedBox.shrink();
              return FutureBuilder<dynamic>(
                future: api.fetchProfile(driver.profileId),
                builder: (context, profileSnapshot) {
                  final profile = profileSnapshot.data as Profile?;
                  return InfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YOUR DRIVER',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B))),
                        Text(profile?.fullName ?? 'Driver',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        if (driver.rating != null)
                          Text(
                            'Rating ${driver.rating!.toStringAsFixed(1)} (${driver.ratingCount})',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        if (driver.licenseNo != null)
                          Text('License ${driver.licenseNo}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
        if (booking.status == BookingStatus.requested) ...[
          const SizedBox(height: 12),
          const ErrorBanner(
            'Waiting for a nearby driver to accept. Drivers online now get this request.',
            tone: Tone.warn,
          ),
        ],
        if (canSos) ...[
          const SizedBox(height: 16),
          SosButton(onActivate: _sendSos),
        ],
        if (booking.status.isActive) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel ride'),
          ),
        ],
        if (booking.status == BookingStatus.completed) ...[
          const SizedBox(height: 12),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rate your driver',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var n = 1; n <= 5; n++)
                      IconButton(
                        onPressed: () => setState(() => _stars = n),
                        icon: Icon(
                          n <= _stars ? Icons.star : Icons.star_border,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: _comment,
                  decoration: const InputDecoration(hintText: 'Optional comment'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _rate,
                  child: const Text('Submit rating'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Book another ride'),
          ),
        ],
        if (booking.status == BookingStatus.cancelled ||
            booking.status == BookingStatus.noShow ||
            booking.status == BookingStatus.expired) ...[
          const SizedBox(height: 12),
          ErrorBanner(
            booking.status == BookingStatus.expired
                ? 'No driver accepted this request in time. Try booking again.'
                : booking.cancelReason != null
                    ? 'Reason: ${booking.cancelReason}'
                    : 'This trip was closed.',
            tone: booking.status == BookingStatus.expired ? Tone.warn : Tone.muted,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Book another ride'),
          ),
        ],
      ],
    );
  }
}

Tone? _toneFor(BookingStatus status) => switch (status) {
      BookingStatus.completed => Tone.good,
      BookingStatus.cancelled => Tone.muted,
      BookingStatus.noShow => Tone.bad,
      BookingStatus.expired => Tone.warn,
      BookingStatus.requested => Tone.warn,
      BookingStatus.assigned || BookingStatus.arrived => Tone.info,
      BookingStatus.inProgress => Tone.good,
    };
