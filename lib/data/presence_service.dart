import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../models/enums.dart';
import '../models/rows.dart';
import 'api.dart';
import 'notification_service.dart';

/// Keeps a driver "online" while the app is backgrounded.
///
/// Runs above the page tree so leaving the dashboard does not stop presence,
/// and uses an Android foreground service so location updates continue with the
/// screen off. While online it also listens to new requests over Supabase
/// Realtime and raises a local notification, so drivers get alerted without a
/// third-party push service.
class PresenceService extends ChangeNotifier {
  PresenceService(this.api, this.notifications);

  final Api api;
  final NotificationService notifications;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<Booking>>? _requestSub;
  Timer? _pingTimer;
  LatLng? _last;
  bool _online = false;
  String? _error;
  bool _firstSnapshot = true;
  final Set<String> _notifiedRequests = <String>{};

  bool get isOnline => _online;
  String? get error => _error;
  LatLng? get lastPosition => _last;

  Future<void> goOnline({required VehicleType vehicleType}) async {
    if (_online) return;
    _online = true;
    _error = null;
    _firstSnapshot = true;
    notifyListeners();

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = 'Location permission is required to go online.';
        _online = false;
        notifyListeners();
        return;
      }

      await notifications.requestPermission();

      final settings = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
              intervalDuration: const Duration(seconds: 15),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'SakayTa — you are online',
                notificationText:
                    'Sharing your location so you receive ride requests.',
                notificationChannelName: 'SakayTa online status',
                enableWakeLock: true,
                notificationIcon:
                    AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            );

      _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          _last = LatLng(position.latitude, position.longitude);
          notifyListeners();
          _push();
        },
        onError: (_) {
          // Keep the ping timer going; a transient GPS error should not drop us.
        },
      );

      _startRequestAlerts(vehicleType);

      // Backup ping so presence stays fresh even without movement.
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _push());
      await _push();
    } catch (e) {
      _error = e.toString();
      _online = false;
      notifyListeners();
    }
  }

  void _startRequestAlerts(VehicleType vehicleType) {
    _requestSub?.cancel();
    _notifiedRequests.clear();
    _requestSub = api.openRequests(vehicleType).listen((requests) {
      if (_firstSnapshot) {
        // Do not blast a notification for requests that were already open when
        // the driver came online.
        _firstSnapshot = false;
        for (final r in requests) {
          _notifiedRequests.add(r.id);
        }
        return;
      }
      for (final request in requests) {
        if (_notifiedRequests.add(request.id)) {
          notifications.show(
            title: 'New ride request',
            body: '${request.originLabel ?? 'Pickup'} → ${request.destLabel ?? 'Dropoff'}'
                ' · ${formatPeso(request.fare)}',
            payload: request.id,
            urgent: true,
          );
        }
      }
    });
  }

  Future<void> goOffline() async {
    if (!_online && _positionSub == null) return;
    _online = false;
    notifyListeners();

    await _positionSub?.cancel();
    _positionSub = null;
    await _requestSub?.cancel();
    _requestSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _notifiedRequests.clear();

    try {
      await api.setPresence(online: false, at: _last);
    } catch (_) {
      // Presence expiry on the server covers a failed final ping.
    }
  }

  Future<void> _push() async {
    if (!_online) return;
    try {
      await api.setPresence(online: true, at: _last);
    } catch (_) {
      // Best effort; the server marks stale drivers offline.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _requestSub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }
}
