import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/offline_queue.dart';
import '../../data/presence_service.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ride_map.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/ui.dart';

const _noShowWaitMinutes = 5;
const _driverCancelReasons = [
  'Passenger not at pickup point',
  'Passenger did not show up',
  'Unit broke down',
  'Road closed or flooded',
  'Passenger asked to cancel',
];

class DriverTripPage extends StatelessWidget {
  const DriverTripPage({super.key});

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
        final bookings = snapshot.data!
          ..sort((a, b) => (b.requestedAt ?? DateTime(0))
              .compareTo(a.requestedAt ?? DateTime(0)));
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
                  title: 'No active trip',
                  description: 'Accepted rides appear here.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/driver'),
                  child: const Text('Back to dashboard'),
                ),
              ],
            ),
          );
        }
        return _DriverTripBody(booking: booking);
      },
    );
  }
}

class _DriverTripBody extends StatefulWidget {
  const _DriverTripBody({required this.booking});
  final Booking booking;

  @override
  State<_DriverTripBody> createState() => _DriverTripBodyState();
}

class _DriverTripBodyState extends State<_DriverTripBody> {
  bool _busy = false;
  String? _message;
  Payment? _payment;

  late final PresenceService _presence;
  RouteResult? _route;
  DateTime? _lastRouteAt;
  LatLng? _lastRouteFrom;
  LatLng? _fallbackPos;

  @override
  void initState() {
    super.initState();
    _loadPayment();
    _presence = context.read<PresenceService>();
    _presence.addListener(_onPresence);
    _loadFallbackPosition();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRoute());
  }

  @override
  void dispose() {
    _presence.removeListener(_onPresence);
    super.dispose();
  }

  void _onPresence() {
    if (!mounted) return;
    setState(() {});
    _maybeRoute();
  }

  Future<void> _loadFallbackPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _fallbackPos = LatLng(pos.latitude, pos.longitude));
      _maybeRoute();
    } catch (_) {
      // no position available
    }
  }

  LatLng? get _myPos => _presence.lastPosition ?? _fallbackPos;

  /// Pickup before the ride starts, destination while underway.
  LatLng? _targetPoint() {
    final b = widget.booking;
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

  Future<void> _maybeRoute() async {
    if (!widget.booking.status.isActive) return;
    final from = _myPos;
    final to = _targetPoint();
    if (from == null || to == null) return;

    final now = DateTime.now();
    final moved =
        _lastRouteFrom == null ? double.infinity : haversineKm(_lastRouteFrom!, from);
    if (_lastRouteAt != null &&
        now.difference(_lastRouteAt!).inSeconds < 20 &&
        moved < 0.05) {
      return;
    }
    _lastRouteAt = now;
    _lastRouteFrom = from;

    try {
      final route = await context.read<Api>().getRoute(from: from, to: to);
      if (mounted && route != null) setState(() => _route = route);
    } catch (_) {
      // straight-line fallback below
    }
  }

  int? _etaMinutes() {
    final to = _targetPoint();
    if (to == null) return null;
    final route = _route;
    if (route != null && route.points.isNotEmpty && route.durationS > 0) {
      return route.etaMinutes;
    }
    final from = _myPos;
    if (from == null) return null;
    return etaMinutes(haversineKm(from, to));
  }

  Future<void> _loadPayment() async {
    try {
      final payment = await context.read<Api>().fetchPayment(widget.booking.id);
      if (mounted) setState(() => _payment = payment);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _transition(BookingStatus to, {String? note}) async {
    final api = context.read<Api>();
    final offline = context.read<OfflineQueue>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await api.transition(widget.booking.id, to, note: note);
      await _loadPayment();
    } catch (_) {
      await offline.addTransition(widget.booking.id, to, note);
      if (mounted) {
        setState(() => _message =
            'No connection. The action is saved and will send when signal returns.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _collected() async {
    final api = context.read<Api>();
    setState(() => _busy = true);
    try {
      await api.markPayment(widget.booking.id, PaymentStatus.collected);
      await _loadPayment();
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      await api.insertSos(bookingId: widget.booking.id, triggeredBy: userId, at: at);
    } catch (_) {
      await offline.addSos(
            bookingId: widget.booking.id,
            triggeredBy: userId,
            at: at,
          );
    }
  }

  Future<void> _cancel() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Reason for cancelling',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final r in _driverCancelReasons)
              ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)),
          ],
        ),
      ),
    );
    if (reason == null) return;
    await _transition(BookingStatus.cancelled, note: reason);
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final api = context.read<Api>();
    final waitMinutes = minutesSince(booking.arrivedAt ?? booking.assignedAt);
    final canNoShow =
        (booking.status == BookingStatus.assigned ||
            booking.status == BookingStatus.arrived) &&
        (waitMinutes ?? 0) >= _noShowWaitMinutes;
    final canSos = {
      BookingStatus.assigned,
      BookingStatus.arrived,
      BookingStatus.inProgress,
    }.contains(booking.status);

    final myPos = _myPos;
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
      if (myPos != null)
        RideMarker(
          id: 'me',
          point: myPos,
          label: 'You',
          kind: MapMarkerKind.driver,
        ),
    ];
    final polylines = <List<LatLng>>[
      if (_route != null && _route!.points.isNotEmpty) _route!.points,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(booking.status.label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text('Trip ${shortId(booking.id)} · ${booking.vehicleType.label}',
            style: const TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 12),
        if (_message != null) ...[
          ErrorBanner(_message!, tone: Tone.warn),
          const SizedBox(height: 12),
        ],
        if (markers.isNotEmpty) ...[
          RideMap(markers: markers, polylines: polylines, center: markers.first.point),
          const SizedBox(height: 12),
        ],
        if (booking.status.isActive && _targetPoint() != null) ...[
          ErrorBanner(
            _etaMinutes() == null
                ? (booking.status == BookingStatus.inProgress
                    ? 'Heading to ${booking.destLabel ?? 'destination'}'
                    : 'Heading to pickup')
                : (booking.status == BookingStatus.inProgress
                    ? '~${_etaMinutes()} min to ${booking.destLabel ?? 'destination'}'
                    : '~${_etaMinutes()} min to pickup'),
            tone: Tone.info,
          ),
          const SizedBox(height: 12),
        ],
        FutureBuilder<Profile?>(
          future: api.fetchProfile(booking.passengerId),
          builder: (context, snapshot) {
            final passenger = snapshot.data;
            return InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PASSENGER',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B))),
                  Text(passenger?.fullName ?? 'Passenger',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    '${booking.passengerCount} passenger${booking.passengerCount > 1 ? 's' : ''}'
                    '${booking.hasLuggage ? ' · with luggage or market goods' : ''}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  Text(
                    'Pickup: ${booking.originLabel ?? 'point'} · Dropoff: ${booking.destLabel ?? 'point'}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        InfoCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fixed fare to collect',
                  style: TextStyle(color: Color(0xFF64748B))),
              Text(formatPeso(booking.fare),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        if (canSos) ...[
          const SizedBox(height: 16),
          SosButton(onActivate: _sendSos, label: 'Hold for driver SOS'),
        ],
        const SizedBox(height: 12),
        if (booking.status == BookingStatus.assigned)
          FilledButton(
            onPressed: _busy ? null : () => _transition(BookingStatus.arrived),
            child: const Text('I have arrived at pickup'),
          ),
        if (booking.status == BookingStatus.arrived)
          FilledButton(
            onPressed: _busy ? null : () => _transition(BookingStatus.inProgress),
            child: const Text('Start trip'),
          ),
        if (booking.status == BookingStatus.inProgress)
          FilledButton(
            onPressed: _busy ? null : () => _transition(BookingStatus.completed),
            child: const Text('Complete trip'),
          ),
        if (booking.status == BookingStatus.completed) ...[
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _payment?.status == PaymentStatus.paid
                      ? 'Paid via ${_payment?.provider ?? 'e-wallet'}'
                      : (_payment?.status == PaymentStatus.collected
                          ? 'Cash collected'
                          : 'Collect cash from passenger'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_payment != null)
                  Text(
                    'Fare ${formatPeso(_payment!.amount)} · commission ${formatPeso(_payment!.commission)} · your net ${formatPeso(_payment!.driverNet)}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                const SizedBox(height: 8),
                if (_payment?.status != PaymentStatus.collected &&
                    _payment?.status != PaymentStatus.paid)
                  FilledButton(
                    onPressed: _busy ? null : _collected,
                    child: const Text('Mark cash collected'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.go('/driver'),
            child: const Text('Back to dashboard'),
          ),
        ],
        if (canNoShow) ...[
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBE123C)),
            onPressed: _busy
                ? null
                : () => _transition(BookingStatus.noShow,
                    note: 'Waited $_noShowWaitMinutes minutes'),
            child: Text('Passenger did not show (waited $_noShowWaitMinutes min)'),
          ),
        ],
        if (booking.status == BookingStatus.assigned ||
            booking.status == BookingStatus.arrived) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel this ride'),
          ),
        ],
      ],
    );
  }
}
