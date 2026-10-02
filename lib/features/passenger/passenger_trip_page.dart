import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/notification_service.dart';
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

  StreamSubscription<Driver?>? _driverSub;
  Driver? _driver;
  RouteResult? _route;
  DateTime? _lastRouteAt;
  LatLng? _lastRouteFrom;
  bool _arriving = false;
  bool _arrivingNotified = false;

  @override
  void initState() {
    super.initState();
    _subscribeDriver();
  }

  @override
  void didUpdateWidget(covariant _TripBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.driverId != widget.booking.driverId) {
      _route = null;
      _arriving = false;
      _arrivingNotified = false;
      _subscribeDriver();
    }
  }

  @override
  void dispose() {
    _driverSub?.cancel();
    _comment.dispose();
    super.dispose();
  }

  void _subscribeDriver() {
    _driverSub?.cancel();
    final driverId = widget.booking.driverId;
    if (driverId == null) {
      _driver = null;
      return;
    }
    _driverSub = context.read<Api>().driverById(driverId).listen((driver) {
      if (!mounted) return;
      setState(() => _driver = driver);
      _maybeComputeRoute();
      _checkArrival();
    });
  }

  LatLng? get _driverPos {
    final d = _driver;
    if (d?.lastLat == null || d?.lastLng == null) return null;
    return LatLng(d!.lastLat!, d.lastLng!);
  }

  /// Where the driver is heading right now: pickup, then dropoff.
  LatLng? _targetPoint(Booking b) {
    if (b.status == BookingStatus.assigned || b.status == BookingStatus.arrived) {
      if (b.originLat != null && b.originLng != null) {
        return LatLng(b.originLat!, b.originLng!);
      }
    }
    if (b.status == BookingStatus.inProgress) {
      if (b.destLat != null && b.destLng != null) {
        return LatLng(b.destLat!, b.destLng!);
      }
    }
    return null;
  }

  Future<void> _maybeComputeRoute() async {
    final booking = widget.booking;
    if (!booking.status.isActive) return;
    final from = _driverPos;
    final to = _targetPoint(booking);
    if (from == null || to == null) return;

    final now = DateTime.now();
    final movedKm = _lastRouteFrom == null ? double.infinity : haversineKm(_lastRouteFrom!, from);
    // Throttle: at most every 20s, and only if the driver moved ~50 m.
    if (_lastRouteAt != null &&
        now.difference(_lastRouteAt!).inSeconds < 20 &&
        movedKm < 0.05) {
      return;
    }
    _lastRouteAt = now;
    _lastRouteFrom = from;

    try {
      final route = await context.read<Api>().getRoute(from: from, to: to);
      if (mounted && route != null) setState(() => _route = route);
    } catch (_) {
      // keep the straight-line fallback
    }
  }

  void _checkArrival() {
    final booking = widget.booking;
    if (booking.status != BookingStatus.inProgress || _arrivingNotified) return;
    final driverPos = _driverPos;
    if (driverPos == null || booking.destLat == null || booking.destLng == null) return;
    final to = LatLng(booking.destLat!, booking.destLng!);
    if (haversineKm(driverPos, to) <= 0.15) {
      _arrivingNotified = true;
      setState(() => _arriving = true);
      context.read<NotificationService>().show(
            title: 'Arriving now',
            body: 'You are almost at ${booking.destLabel ?? 'your destination'}.',
            payload: booking.id,
            urgent: true,
          );
    }
  }

  /// Minutes remaining, route-based when available, straight-line otherwise.
  int? _etaMinutes() {
    final to = _targetPoint(widget.booking);
    if (to == null) return null;
    final route = _route;
    if (route != null && route.points.isNotEmpty && route.durationS > 0) {
      return route.etaMinutes;
    }
    final from = _driverPos;
    if (from == null) return null;
    return etaMinutes(haversineKm(from, to));
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
    final canSos = {
      BookingStatus.assigned,
      BookingStatus.arrived,
      BookingStatus.inProgress,
    }.contains(booking.status);

    final driverPos = _driverPos;
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
      if (driverPos != null)
        RideMarker(
          id: 'driver',
          point: driverPos,
          label: 'Your driver',
          kind: MapMarkerKind.driver,
        ),
    ];
    final polylines = <List<LatLng>>[
      if (_route != null && _route!.points.isNotEmpty) _route!.points,
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
          RideMap(markers: markers, polylines: polylines, center: markers.first.point),
          const SizedBox(height: 12),
        ],
        _StatusBanner(
          booking: booking,
          etaMinutes: _etaMinutes(),
          arriving: _arriving,
          hasDriverFix: driverPos != null,
        ),
        const SizedBox(height: 12),
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
        if (_driver != null) ...[
          const SizedBox(height: 12),
          _DriverCard(driver: _driver!, booking: booking),
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
                Text('You have arrived at ${booking.destLabel ?? 'your destination'}.',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Rate your driver',
                    style: TextStyle(fontWeight: FontWeight.w700)),
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

class _DriverCard extends StatefulWidget {
  const _DriverCard({required this.driver, required this.booking});
  final Driver driver;
  final Booking booking;

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverInfo {
  const _DriverInfo({this.profile, this.vehicle, this.driverPhoto, this.vehiclePhoto});
  final Profile? profile;
  final Vehicle? vehicle;
  final String? driverPhoto;
  final String? vehiclePhoto;
}

class _DriverCardState extends State<_DriverCard> {
  late Future<_DriverInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DriverInfo> _load() async {
    final api = context.read<Api>();
    final profile = await api.fetchProfile(widget.driver.profileId);
    final vehicle = await api.fetchVehicle(widget.driver.id);
    final driverPhoto = await api.signedPhotoUrl(widget.driver.photoUrl);
    final vehiclePhoto = await api.signedPhotoUrl(vehicle?.photoUrl);
    return _DriverInfo(
      profile: profile,
      vehicle: vehicle,
      driverPhoto: driverPhoto,
      vehiclePhoto: vehiclePhoto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return FutureBuilder<_DriverInfo>(
      future: _future,
      builder: (context, snapshot) {
        final info = snapshot.data;
        return InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('YOUR DRIVER',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFFE2E8F0),
                      child: (info?.driverPhoto == null)
                          ? const Icon(Icons.person, color: Color(0xFF64748B))
                          : Image.network(info!.driverPhoto!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.person, color: Color(0xFF64748B))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info?.profile?.fullName ?? 'Driver',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        if (d.rating != null)
                          Text('Rating ${d.rating!.toStringAsFixed(1)} (${d.ratingCount})',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B))),
                        if (info?.vehicle != null)
                          Text(
                            '${info!.vehicle!.type.label} · Unit ${info.vehicle!.unitNo ?? '—'} · Plate ${info.vehicle!.plateNo ?? '—'}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        if (d.licenseNo != null)
                          Text('License ${d.licenseNo}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
              if (info?.vehiclePhoto != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    info!.vehiclePhoto!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Vehicle photo',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.booking,
    required this.etaMinutes,
    required this.arriving,
    required this.hasDriverFix,
  });

  final Booking booking;
  final int? etaMinutes;
  final bool arriving;
  final bool hasDriverFix;

  @override
  Widget build(BuildContext context) {
    if (booking.status == BookingStatus.assigned ||
        booking.status == BookingStatus.arrived) {
      final eta = etaMinutes == null
          ? (hasDriverFix ? 'Driver is on the way' : 'Locating your driver…')
          : (etaMinutes! <= 1 ? 'Driver is arriving now' : 'Driver is ~$etaMinutes min away');
      return ErrorBanner(eta, tone: Tone.info);
    }
    if (booking.status == BookingStatus.inProgress) {
      if (arriving) {
        return const ErrorBanner('Arriving now — please get ready to alight.',
            tone: Tone.good);
      }
      final eta = etaMinutes == null
          ? 'On the way'
          : (etaMinutes! <= 1 ? 'Arriving now' : '~$etaMinutes min to ${booking.destLabel ?? 'destination'}');
      return ErrorBanner(eta, tone: Tone.good);
    }
    return const SizedBox.shrink();
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
