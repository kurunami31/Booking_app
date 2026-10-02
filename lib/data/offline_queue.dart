import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/geo.dart';
import '../models/enums.dart';
import 'api.dart';

/// Offline action queue backed by SharedPreferences.
///
/// Bookings, status changes, and SOS attempts made without a connection are
/// stored on the device and replayed when the network returns. A failed replay
/// stops the queue rather than dropping the action.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(this.api);

  static const _storageKey = 'sakay_ta.queue.v1';
  final Api api;
  final List<_QueuedAction> _items = [];
  final Random _random = Random();

  int get pending => _items.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _items.clear();
    if (raw != null) {
      final decoded = jsonDecode(raw) as List;
      for (final item in decoded) {
        _items.add(_QueuedAction.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_items.map((i) => i.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> addBookingRequest(Map<String, dynamic> payload) async {
    _items.add(_QueuedAction(
      id: _newId(),
      kind: 'request_booking',
      payload: payload,
    ));
    await _persist();
  }

  Future<void> addTransition(String bookingId, BookingStatus to, String? note) async {
    _items.add(_QueuedAction(
      id: _newId(),
      kind: 'transition_booking',
      payload: {'booking_id': bookingId, 'to': to.db, 'note': note},
    ));
    await _persist();
  }

  Future<void> addSos({
    required String bookingId,
    required String triggeredBy,
    LatLng? at,
  }) async {
    _items.add(_QueuedAction(
      id: _newId(),
      kind: 'sos_alert',
      payload: {
        'booking_id': bookingId,
        'triggered_by': triggeredBy,
        'lat': at?.lat,
        'lng': at?.lng,
      },
    ));
    await _persist();
  }

  /// Attempts to send queued actions. Stops at the first failure.
  Future<void> flush() async {
    if (_items.isEmpty) return;
    while (_items.isNotEmpty) {
      final ok = await _process(_items.first);
      if (!ok) break;
      _items.removeAt(0);
      await _persist();
    }
  }

  Future<bool> _process(_QueuedAction action) async {
    try {
      switch (action.kind) {
        case 'request_booking':
          final p = action.payload;
          await api.requestBooking(
            vehicleType: VehicleType.fromDb(p['vehicle_type'] as String),
            originZone: p['origin_zone'] as String,
            destZone: p['dest_zone'] as String,
            originLat: (p['origin_lat'] as num?)?.toDouble(),
            originLng: (p['origin_lng'] as num?)?.toDouble(),
            originLabel: p['origin_label'] as String?,
            destLat: (p['dest_lat'] as num?)?.toDouble(),
            destLng: (p['dest_lng'] as num?)?.toDouble(),
            destLabel: p['dest_label'] as String?,
            discount: DiscountType.fromDb(p['discount_type'] as String?),
            passengerCount: (p['passenger_count'] as num?)?.toInt() ?? 1,
            hasLuggage: (p['has_luggage'] as bool?) ?? false,
          );
          return true;
        case 'transition_booking':
          final p = action.payload;
          await api.transition(
            p['booking_id'] as String,
            BookingStatus.fromDb(p['to'] as String),
            note: p['note'] as String?,
          );
          return true;
        case 'sos_alert':
          final p = action.payload;
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          await api.insertSos(
            bookingId: p['booking_id'] as String,
            triggeredBy: p['triggered_by'] as String,
            at: lat != null && lng != null ? LatLng(lat, lng) : null,
          );
          return true;
        default:
          return true; // drop unknown actions so the queue is not stuck
      }
    } catch (_) {
      return false;
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}

class _QueuedAction {
  _QueuedAction({required this.id, required this.kind, required this.payload});

  final String id;
  final String kind;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'payload': payload};

  factory _QueuedAction.fromJson(Map<String, dynamic> json) => _QueuedAction(
        id: json['id'] as String,
        kind: json['kind'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}
