import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../data/reference_controller.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';

class AdminFaresPage extends StatefulWidget {
  const AdminFaresPage({super.key});

  @override
  State<AdminFaresPage> createState() => _AdminFaresPageState();
}

class _AdminFaresPageState extends State<AdminFaresPage> {
  final _fareControllers = <String, TextEditingController>{};
  final _base = TextEditingController();
  final _perKm = TextEditingController();
  final _commission = TextEditingController();
  final _discount = TextEditingController();

  final _newFare = TextEditingController();
  String? _newOrigin;
  String? _newDest;
  VehicleType _newType = VehicleType.tricycle;

  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    for (final c in _fareControllers.values) {
      c.dispose();
    }
    _base.dispose();
    _perKm.dispose();
    _commission.dispose();
    _discount.dispose();
    _newFare.dispose();
    super.dispose();
  }

  void _syncControllers(ReferenceController reference) {
    for (final row in reference.matrix) {
      _fareControllers.putIfAbsent(
        row.id,
        () => TextEditingController(text: row.fare.toStringAsFixed(0)),
      );
    }
    _base.text = reference.settings.baseFare.toStringAsFixed(0);
    _perKm.text = reference.settings.perKmRate.toStringAsFixed(0);
    _commission.text = reference.settings.commissionRate.toString();
    _discount.text = reference.settings.discountRate.toString();
  }

  Future<void> _saveMatrix() async {
    final reference = context.read<ReferenceController>();
    final client = Supabase.instance.client;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      for (final row in reference.matrix) {
        final controller = _fareControllers[row.id];
        if (controller == null) continue;
        final value = double.tryParse(controller.text);
        if (value == null || value < 0) {
          throw Exception('Invalid fare for a route');
        }
        if (value != row.fare) {
          await client.from('fare_matrix').update({'fare': value}).eq('id', row.id);
        }
      }
      await reference.load();
      if (mounted) setState(() => _message = 'Fares saved.');
    } on PostgrestException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings() async {
    final reference = context.read<ReferenceController>();
    final client = Supabase.instance.client;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final values = {
        'base_fare': _base.text,
        'per_km_rate': _perKm.text,
        'commission_rate': _commission.text,
        'discount_rate': _discount.text,
      };
      for (final entry in values.entries) {
        final parsed = double.tryParse(entry.value);
        if (parsed == null) throw Exception('Invalid value for ${entry.key}');
        await client
            .from('app_settings')
            .update({'value': parsed, 'updated_at': DateTime.now().toUtc().toIso8601String()})
            .eq('key', entry.key);
      }
      await reference.load();
      if (mounted) setState(() => _message = 'Settings saved.');
    } on PostgrestException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPair() async {
    if (_newOrigin == null || _newDest == null) {
      setState(() => _message = 'Choose an origin and a destination zone.');
      return;
    }
    final fare = double.tryParse(_newFare.text);
    if (fare == null || fare < 0) {
      setState(() => _message = 'Enter a valid fare.');
      return;
    }
    final reference = context.read<ReferenceController>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.from('fare_matrix').insert({
        'origin_zone': _newOrigin,
        'dest_zone': _newDest,
        'vehicle_type': _newType.db,
        'fare': fare,
      });
      _newFare.clear();
      await reference.load();
      if (mounted) setState(() => _message = 'Fare pair added.');
    } on PostgrestException catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceController>();

    if (reference.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    _syncControllers(reference);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Fare matrix & settings',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text('Values must match the LGU-approved matrix. [VERIFY ordinance and rates]',
            style: TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 12),
        if (_message != null) ...[
          ErrorBanner(_message!, tone: Tone.info),
          const SizedBox(height: 12),
        ],
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Platform settings'),
              _numField('base_fare', _base),
              _numField('per_km_rate', _perKm),
              _numField('commission_rate', _commission),
              _numField('discount_rate', _discount),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _saveSettings,
                child: const Text('Save settings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Add a fare pair'),
              DropdownButtonFormField<String>(
                initialValue: _newOrigin,
                isExpanded: true,
                hint: const Text('From zone'),
                items: [
                  for (final z in reference.zones)
                    DropdownMenuItem(value: z.id, child: Text(z.name)),
                ],
                onChanged: (v) => setState(() => _newOrigin = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _newDest,
                isExpanded: true,
                hint: const Text('To zone'),
                items: [
                  for (final z in reference.zones)
                    DropdownMenuItem(value: z.id, child: Text(z.name)),
                ],
                onChanged: (v) => setState(() => _newDest = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<VehicleType>(
                initialValue: _newType,
                items: [
                  for (final v in VehicleType.values)
                    DropdownMenuItem(value: v, child: Text(v.label)),
                ],
                onChanged: (v) => setState(() => _newType = v ?? VehicleType.tricycle),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newFare,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fare (PHP)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _addPair,
                child: const Text('Add fare pair'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SectionTitle('Existing fares'),
        if (reference.matrix.isEmpty)
          const EmptyState(title: 'No fare rows yet')
        else
          for (final row in reference.matrix)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${reference.zoneName(row.originZone)} → ${reference.zoneName(row.destZone)}\n${row.vehicleType.label}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _fareControllers[row.id],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _saveMatrix,
          child: const Text('Save fare changes'),
        ),
        const SizedBox(height: 8),
        Text(
          'Current stored total: ${formatPeso(reference.matrix.fold<double>(0, (sum, r) => sum + r.fare))}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label.replaceAll('_', ' ')),
      ),
    );
  }
}
