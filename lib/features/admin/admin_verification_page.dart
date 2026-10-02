import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../models/enums.dart';
import '../../models/rows.dart';
import '../../widgets/ui.dart';

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});

  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage> {
  DriverStatus _filter = DriverStatus.pending;
  bool _loading = true;
  String? _error;
  String? _busyId;
  List<_Candidate> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final driverRows = await client
          .from('drivers')
          .select()
          .eq('status', _filter.db)
          .order('created_at', ascending: false);
      final drivers = driverRows.map((r) => Driver.fromMap(r)).toList();

      if (drivers.isEmpty) {
        setState(() {
          _rows = const [];
          _loading = false;
        });
        return;
      }

      final vehicleRows = await client
          .from('vehicles')
          .select()
          .inFilter('driver_id', drivers.map((d) => d.id).toList());
      final profileRows = await client
          .from('profiles')
          .select()
          .inFilter('id', drivers.map((d) => d.profileId).toList());

      final vehicles = {for (final r in vehicleRows) r['driver_id'] as String: Vehicle.fromMap(r)};
      final profiles = {for (final r in profileRows) r['id'] as String: Profile.fromMap(r)};

      setState(() {
        _rows = [
          for (final d in drivers)
            _Candidate(driver: d, vehicle: vehicles[d.id], profile: profiles[d.profileId]),
        ];
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(Driver driver, Vehicle? vehicle, DriverStatus status) async {
    setState(() {
      _busyId = driver.id;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.from('drivers').update({'status': status.db}).eq('id', driver.id);
      if (vehicle != null) {
        await client
            .from('vehicles')
            .update({'verified': status == DriverStatus.verified}).eq('id', vehicle.id);
      }
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Driver & vehicle verification',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text(
          'Check the license and franchise number against the LGU list before approving.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        const ErrorBanner(
          'Photo and ID checks are manual. This MVP records a link only. [VERIFY document requirements and retention with the LGU and NPC]',
          tone: Tone.warn,
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        SegmentedButton<DriverStatus>(
          segments: const [
            ButtonSegment(value: DriverStatus.pending, label: Text('Pending')),
            ButtonSegment(value: DriverStatus.verified, label: Text('Verified')),
            ButtonSegment(value: DriverStatus.suspended, label: Text('Suspended')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) {
            setState(() => _filter = s.first);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_rows.isEmpty)
          EmptyState(title: 'No ${_filter.label.toLowerCase()} drivers')
        else
          for (final candidate in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(candidate.profile?.fullName ?? 'Unnamed driver',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                '${shortId(candidate.driver.id)} · applied ${formatDateTime(candidate.driver.createdAt)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(candidate.driver.status.label,
                            tone: candidate.driver.status == DriverStatus.verified
                                ? Tone.good
                                : candidate.driver.status == DriverStatus.suspended
                                    ? Tone.bad
                                    : Tone.warn),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'License: ${candidate.driver.licenseNo ?? '—'}\n'
                      'Vehicle: ${candidate.vehicle?.type.label ?? '—'}\n'
                      'Unit / Plate: ${candidate.vehicle?.unitNo ?? '—'} / ${candidate.vehicle?.plateNo ?? '—'}\n'
                      'Franchise: ${candidate.vehicle?.franchiseNo ?? '—'}\n'
                      'Trips: completed ${candidate.driver.completedCount} · cancelled ${candidate.driver.cancelledCount}'
                      '${candidate.driver.rating != null ? ' · rating ${candidate.driver.rating!.toStringAsFixed(1)} (${candidate.driver.ratingCount})' : ''}',
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _PhotoThumb(
                                path: candidate.driver.photoUrl, label: 'Driver selfie')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _PhotoThumb(
                                path: candidate.vehicle?.photoUrl, label: 'Vehicle')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busyId == candidate.driver.id
                                ? null
                                : () => _setStatus(candidate.driver, candidate.vehicle,
                                    DriverStatus.verified),
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFBE123C)),
                            onPressed: _busyId == candidate.driver.id
                                ? null
                                : () => _setStatus(candidate.driver, candidate.vehicle,
                                    DriverStatus.suspended),
                            child: const Text('Suspend'),
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
  }
}

class _Candidate {
  const _Candidate({required this.driver, this.vehicle, this.profile});
  final Driver driver;
  final Vehicle? vehicle;
  final Profile? profile;
}

class _PhotoThumb extends StatefulWidget {
  const _PhotoThumb({required this.path, required this.label});
  final String? path;
  final String label;

  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<String?> _resolve() async {
    final p = widget.path;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    try {
      return await Supabase.instance.client.storage
          .from('driver-photos')
          .createSignedUrl(p, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 90,
                width: double.infinity,
                color: const Color(0xFFE2E8F0),
                child: url == null
                    ? const Icon(Icons.image_not_supported_outlined,
                        color: Color(0xFF94A3B8))
                    : Image.network(url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF94A3B8))),
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        );
      },
    );
  }
}
