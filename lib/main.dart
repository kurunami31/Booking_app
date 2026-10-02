import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'data/api.dart';
import 'data/auth_controller.dart';
import 'data/notification_service.dart';
import 'data/offline_queue.dart';
import 'data/passenger_alert_service.dart';
import 'data/presence_service.dart';
import 'data/reference_controller.dart';
import 'models/enums.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Legacy JWT anon key for this project. Migrate to publishableKey when
      // the project moves to the new API keys. [VERIFY]
      // ignore: deprecated_member_use
      anonKey: AppConfig.supabaseAnonKey,
    );
  } else {
    runApp(const _ConfigMissingApp());
    return;
  }

  final api = Api();
  final auth = AuthController(api);
  final reference = ReferenceController(api);
  final offline = OfflineQueue(api);
  final notifications = NotificationService();
  await notifications.init();
  final presence = PresenceService(api, notifications);
  final passengerAlerts = PassengerAlertService(api, notifications);

  await auth.init();
  await reference.load();
  await offline.load();
  await offline.flush();

  // Keep passenger alerts in step with who is signed in.
  auth.addListener(() {
    passengerAlerts.syncFor(
      passengerId: auth.role == UserRole.passenger ? auth.userId : null,
    );
  });

  runApp(
    MultiProvider(
      providers: [
        Provider<Api>.value(value: api),
        Provider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<ReferenceController>.value(value: reference),
        ChangeNotifierProvider<OfflineQueue>.value(value: offline),
        ChangeNotifierProvider<PresenceService>.value(value: presence),
      ],
      child: const SakayTaApp(),
    ),
  );
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SakayTa',
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                ErrorBanner(
                  'Supabase is not configured. Run the app with:\n\nflutter run --dart-define-from-file=env.json',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
