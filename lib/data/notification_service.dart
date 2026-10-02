import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local, on-device notifications. No external push service.
///
/// Job alerts are delivered over Supabase Realtime while the driver's
/// foreground service is running; this class just raises the visible
/// notification. Firebase/ FCM can replace or complement this later without
/// changing callers.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'sakayta_alerts';
  static const _channelName = 'SakayTa alerts';
  static const _channelDescription = 'Ride requests and trip updates';

  Future<void> init() async {
    if (kIsWeb) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    if (kIsWeb || !_ready) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<void> show({
    required String title,
    required String body,
    String? payload,
    bool urgent = false,
  }) async {
    if (kIsWeb || !_ready) return;
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: urgent ? Importance.max : Importance.high,
      priority: urgent ? Priority.max : Priority.high,
      category: AndroidNotificationCategory.message,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: payload,
    );
  }
}
