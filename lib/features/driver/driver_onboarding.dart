import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_controller.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';

class DriverOnboardingForm extends StatefulWidget {
  const DriverOnboardingForm({super.key});

  @override
  State<DriverOnboardingForm> createState() => _DriverOnboardingFormState();
}

class _DriverOnboardingFormState extends State<DriverOnboardingForm> {
  final _license = TextEditingController();
  final _idPhoto = TextEditingController();
  final _unit = TextEditingController();
  final _plate = TextEditingController();
  final _franchise = TextEditingController();
  VehicleType _vehicleType = VehicleType.tricycle;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _license.dispose();
    _idPhoto.dispose();
    _unit.dispose();
    _plate.dispose();
    _franchise.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final userId = auth.userId;
    if (userId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final driver = await Supabase.instance.client
          .from('drivers')
          .insert({
            'profile_id': userId,
            'license_no': _license.text.trim(),
            'id_photo_url': _idPhoto.text.trim().isEmpty ? null : _idPhoto.text.trim(),
          })
          .select('id')
          .single();

      await Supabase.instance.client.from('vehicles').insert({
        'driver_id': driver['id'],
        'type': _vehicleType.db,
        'unit_no': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        'plate_no': _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        'franchise_no': _franchise.text.trim().isEmpty ? null : _franchise.text.trim(),
      });

      await auth.refresh();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Driver onboarding',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text(
          'Your details are recorded and must be verified by the LGU desk before you can take rides.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        const ErrorBanner(
          'Verification is manual in this MVP. An admin reviews your license and franchise number against the LGU list. Photo upload is not built; paste a link to your ID photo.',
          tone: Tone.warn,
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel("Driver's license number", required: true),
              TextField(controller: _license),
              const FieldLabel('ID photo link',
                  hint: 'Link to your license or a clear photo. [VERIFY storage policy with NPC]'),
              TextField(controller: _idPhoto, keyboardType: TextInputType.url),
              const FieldLabel('Vehicle type', required: true),
              DropdownButtonFormField<VehicleType>(
                initialValue: _vehicleType,
                items: [
                  for (final v in VehicleType.values)
                    DropdownMenuItem(value: v, child: Text(v.label)),
                ],
                onChanged: (v) => setState(() => _vehicleType = v ?? VehicleType.tricycle),
              ),
              const FieldLabel('Unit / body number'),
              TextField(controller: _unit),
              const FieldLabel('Plate number'),
              TextField(controller: _plate),
              const FieldLabel('Franchise / registration number',
                  hint: 'From your LGU franchise. [VERIFY format]'),
              TextField(controller: _franchise),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit for verification'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DriverPendingView extends StatelessWidget {
  const DriverPendingView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final driver = auth.driver;
    final vehicle = auth.vehicle;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Verification pending',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const ErrorBanner(
          'You cannot accept rides until an admin marks your driver record and vehicle as verified.',
          tone: Tone.warn,
        ),
        const SizedBox(height: 12),
        InfoCard(
          child: Text(
            'License: ${driver?.licenseNo ?? '—'}\n'
            'Vehicle: ${vehicle == null ? '—' : '${vehicle.type.label} · Unit ${vehicle.unitNo ?? '—'} · Plate ${vehicle.plateNo ?? '—'}'}\n'
            'Franchise: ${vehicle?.franchiseNo ?? '—'}',
            style: const TextStyle(height: 1.6),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.read<AuthController>().refresh(),
          child: const Text('Check status again'),
        ),
      ],
    );
  }
}

class DriverSuspendedView extends StatelessWidget {
  const DriverSuspendedView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Account suspended',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          ErrorBanner(
            'Contact the LGU desk or the operator to resolve this. Suspended accounts cannot go online.',
          ),
        ],
      ),
    );
  }
}
