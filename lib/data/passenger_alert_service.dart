import 'dart:async';

import '../models/enums.dart';
import '../models/rows.dart';
import 'api.dart';
import 'notification_service.dart';

/// Notifies a passenger when their ride changes state, delivered over Supabase
/// Realtime to a local notification. No external push service.
class PassengerAlertService {
  PassengerAlertService(this.api, this.notifications);

  final Api api;
  final NotificationService notifications;

  StreamSubscription<List<Booking>>? _sub;
  String? _passengerId;
  final Map<String, String> _lastStatus = <String, String>{};

  static const _notifyOn = {
    BookingStatus.assigned,
    BookingStatus.arrived,
    BookingStatus.inProgress,
    BookingStatus.completed,
  };

  /// Idempotent: starts for a passenger, stops when called with null.
  void syncFor({required String? passengerId}) {
    if (passengerId == null) {
      stop();
      return;
    }
    if (_passengerId == passengerId) return;
    stop();
    _passengerId = passengerId;
    _sub = api.bookingsForPassenger(passengerId).listen((bookings) {
      for (final booking in bookings) {
        final previous = _lastStatus[booking.id];
        if (previous != null &&
            previous != booking.status.db &&
            _notifyOn.contains(booking.status)) {
          notifications.show(
            title: booking.status.label,
            body:
                '${booking.originLabel ?? 'Pickup'} → ${booking.destLabel ?? 'Dropoff'}',
            payload: booking.id,
          );
        }
        _lastStatus[booking.id] = booking.status.db;
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _passengerId = null;
    _lastStatus.clear();
  }
}
