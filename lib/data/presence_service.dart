import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import 'api.dart';

/// Keeps a driver "online" while the app is backgrounded.
///
/// Runs above the page tree so leaving the dashboard does not stop presence,
/// and uses an Android foreground service so location updates continue with the
/// screen off. Presence is pinged on an interval regardless of whether the
/// position changed, so a stationary driver does not look stale.
class PresenceService extends ChangeNotifier {
  PresenceService(this.api);

  final Api api;

  StreamSubscription<Position>? _positionSub;
  Timer? _pingTimer;
  LatLng? _last;
  bool _online = false;
  String? _error;

  bool get isOnline => _online;
  String? get error => _error;
  LatLng? get lastPosition => _last;

  Future<void> goOnline() async {
    if (_online) return;
    _online = true;
    _error = null;
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
          _push();
        },
        onError: (_) {
          // Keep the ping timer going; a transient GPS error should not drop us.
        },
      );

      // Backup ping so presence stays fresh even without movement.
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _push());
      await _push();
    } catch (e) {
      _error = e.toString();
      _online = false;
      notifyListeners();
    }
  }

  Future<void> goOffline() async {
    if (!_online && _positionSub == null) return;
    _online = false;
    notifyListeners();

    await _positionSub?.cancel();
    _positionSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;

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
    _pingTimer?.cancel();
    super.dispose();
  }
}
