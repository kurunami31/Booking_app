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
import '../../widgets/ui.dart';

class PassengerHomePage extends StatefulWidget {
  const PassengerHomePage({super.key});

  @override
  State<PassengerHomePage> createState() => _PassengerHomePageState();
}

class _PassengerHomePageState extends State<PassengerHomePage> {
  VehicleType _vehicleType = VehicleType.tricycle;
  String? _originZone;
  String? _destZone;
  final _originLabel = TextEditingController();
  DiscountType? _discount;
  int _passengerCount = 1;
  bool _hasLuggage = false;

  LatLng? _gps;
  bool _locating = false;
  String? _geoError;

  bool _submitting = false;
  String? _message;

  @override
  void dispose() {
    _originLabel.dispose();
    super.dispose();
  }

  String? get _effectiveOriginZone =>
      _originZone ?? _nearest?.id;

  FareZoneCandidate? get _nearest {
    if (_gps == null) return null;
    final zone = context.read<ReferenceController>().nearestZone(_gps!);
    return zone == null
        ? null
        : FareZoneCandidate(zone.id, zone.name);
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _geoError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _geoError = 'Location access was denied. Type a landmark instead.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() => _gps = LatLng(position.latitude, position.longitude));
    } catch (_) {
      setState(() => _geoError = 'Could not get your location. Type a landmark instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirm() async {
    final api = context.read<Api>();
    final offline = context.read<OfflineQueue>();
    final userId = context.read<AuthController>().userId;
    if (userId == null) return;

    final origin = _effectiveOriginZone;
    final dest = _destZone;
    if (origin == null || dest == null) {
      setState(() => _message = 'Choose a pickup and a dropoff point.');
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
    });

    final zone = context.read<ReferenceController>().zoneById(origin);
    final destZone = context.read<ReferenceController>().zoneById(dest);
    final originPoint = _gps != null && _nearest?.id == origin
        ? _gps
        : (zone == null ? null : LatLng(zone.centroidLat, zone.centroidLng));
    final destPoint = destZone == null
        ? null
        : LatLng(destZone.centroidLat, destZone.centroidLng);

    final payload = <String, dynamic>{
      'vehicle_type': _vehicleType.db,
      'origin_zone': origin,
      'dest_zone': dest,
      'origin_lat': originPoint?.lat,
      'origin_lng': originPoint?.lng,
      'origin_label': _originLabel.text.trim().isEmpty
          ? zone?.name
          : _originLabel.text.trim(),
      'dest_lat': destPoint?.lat,
      'dest_lng': destPoint?.lng,
      'dest_label': destZone?.name,
      'discount_type': _discount?.db,
      'passenger_count': _passengerCount,
      'has_luggage': _hasLuggage,
    };

    try {
      await api.requestBooking(
        vehicleType: _vehicleType,
        originZone: origin,
        destZone: dest,
        originLat: originPoint?.lat,
        originLng: originPoint?.lng,
        originLabel: payload['origin_label'] as String?,
        destLat: destPoint?.lat,
        destLng: destPoint?.lng,
        destLabel: destZone?.name,
        discount: _discount,
        passengerCount: _passengerCount,
        hasLuggage: _hasLuggage,
      );
      if (mounted) context.go('/trip');
    } on PostgrestException catch (e) {
      setState(() => _message = e.message);
    } catch (_) {
      await offline.addBookingRequest(payload);
      setState(() => _message =
          'No connection. Your booking is saved on this phone and will be sent when signal returns.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceController>();
    final api = context.read<Api>();
    final userId = context.watch<AuthController>().userId ?? '';

    if (reference.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder(
      stream: api.bookingsForPassenger(userId),
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? const [];
        final active = bookings.where((b) => b.status.isActive).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Book a ride',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text(
              'Fixed fare is shown before you confirm. Cash on board.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            if (active.isNotEmpty) ...[
              InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('You have an active ride',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => context.go('/trip'),
                      child: const Text('View my ride'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (reference.settings.fareMatrixIsPlaceholder)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ErrorBanner(
                  'Fare matrix is still placeholder data. [VERIFY with the LGU-approved rates]',
                  tone: Tone.warn,
                ),
              ),
            if (_message != null) ...[
              ErrorBanner(_message!, tone: Tone.info),
              const SizedBox(height: 12),
            ],
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Vehicle type', required: true),
                  DropdownButtonFormField<VehicleType>(
                    initialValue: _vehicleType,
                    items: [
                      for (final v in VehicleType.values)
                        DropdownMenuItem(
                          value: v,
                          child: Text('${v.label} — ${v.hint}'),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _vehicleType = v ?? VehicleType.tricycle),
                  ),
                  const FieldLabel('Pickup point', required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _effectiveOriginZone,
                    isExpanded: true,
                    items: [
                      for (final zone in reference.zones)
                        DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                    ],
                    onChanged: (v) => setState(() => _originZone = v),
                    hint: const Text('Choose a pickup zone'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _locate,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(_locating ? 'Getting location…' : 'Use my exact location'),
                  ),
                  if (_gps != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'GPS ${_gps!.lat.toStringAsFixed(4)}, ${_gps!.lng.toStringAsFixed(4)}'
                        '${_nearest != null ? ' · nearest zone ${_nearest!.name}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ),
                  if (_geoError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_geoError!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                    ),
                  const FieldLabel('Pickup note (optional)',
                      hint: 'Example: tapat ng palengke gate.'),
                  TextField(
                    controller: _originLabel,
                    decoration: const InputDecoration(
                      hintText: 'Tapat ng palengke, likod ng simbahan…',
                    ),
                  ),
                  const FieldLabel('Dropoff point', required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _destZone,
                    isExpanded: true,
                    items: [
                      for (final zone in reference.zones)
                        DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                    ],
                    onChanged: (v) => setState(() => _destZone = v),
                    hint: const Text('Choose a dropoff zone'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Discount', hint: 'ID is checked by the driver on board.'),
                  DropdownButtonFormField<DiscountType?>(
                    initialValue: _discount,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final d in DiscountType.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (v) => setState(() => _discount = v),
                  ),
                  const FieldLabel('Passengers'),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() =>
                            _passengerCount = (_passengerCount - 1).clamp(1, 12)),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_passengerCount',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      IconButton(
                        onPressed: () => setState(() =>
                            _passengerCount = (_passengerCount + 1).clamp(1, 12)),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: _hasLuggage,
                    onChanged: (v) => setState(() => _hasLuggage = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I have luggage or market goods (may need a tuk-tuk/bao-bao)',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FareCard(
              reference: reference,
              vehicleType: _vehicleType,
              originZone: _effectiveOriginZone,
              destZone: _destZone,
              origin: _gps,
              discount: _discount,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_submitting ||
                      _effectiveOriginZone == null ||
                      _destZone == null)
                  ? null
                  : _confirm,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirm booking'),
            ),
          ],
        );
      },
    );
  }
}

class FareZoneCandidate {
  const FareZoneCandidate(this.id, this.name);
  final String id;
  final String name;
}

class _FareCard extends StatelessWidget {
  const _FareCard({
    required this.reference,
    required this.vehicleType,
    required this.originZone,
    required this.destZone,
    required this.origin,
    required this.discount,
  });

  final ReferenceController reference;
  final VehicleType vehicleType;
  final String? originZone;
  final String? destZone;
  final LatLng? origin;
  final DiscountType? discount;

  @override
  Widget build(BuildContext context) {
    final hasZones = originZone != null && destZone != null;
    final fare = hasZones
        ? reference.previewFare(
            vehicleType: vehicleType,
            originZone: originZone,
            destZone: destZone,
            origin: origin,
            discount: discount,
          )
        : null;
    final approved = reference.hasMatrixRate(originZone, destZone, vehicleType);

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR FARE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                fare == null ? '—' : formatPeso(fare),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              if (discount != null) const StatusPill('Discounted', tone: Tone.warn),
            ],
          ),
          if (fare != null && !approved)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'No approved fare matrix for this pair yet. Showing a computed fare. [VERIFY with LGU fare matrix]',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'This is the fixed fare. It will not change on the street.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }
}
