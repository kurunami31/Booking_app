import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/auth_controller.dart';
import 'data/offline_queue.dart';
import 'data/presence_service.dart';
import 'features/admin/admin_fares_page.dart';
import 'features/admin/admin_live_page.dart';
import 'features/admin/admin_reports_page.dart';
import 'features/admin/admin_sos_page.dart';
import 'features/admin/admin_verification_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/driver/driver_earnings_page.dart';
import 'features/driver/driver_home_page.dart';
import 'features/driver/driver_trip_page.dart';
import 'features/passenger/passenger_history_page.dart';
import 'features/passenger/passenger_home_page.dart';
import 'features/passenger/passenger_trip_page.dart';
import 'models/enums.dart';
import 'widgets/ui.dart';

class SakayTaApp extends StatefulWidget {
  const SakayTaApp({super.key});

  @override
  State<SakayTaApp> createState() => _SakayTaAppState();
}

class _SakayTaAppState extends State<SakayTaApp> {
  late final GoRouter _router;
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(context.read<AuthController>());
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      context.read<OfflineQueue>().flush();
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SakayTa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}

String _roleHome(UserRole? role) => switch (role) {
      UserRole.driver => '/driver',
      UserRole.admin => '/admin',
      _ => '/',
    };

GoRouter _buildRouter(AuthController auth) {
  return GoRouter(
    refreshListenable: auth,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!auth.isSignedIn) {
        return loc == '/signin' ? null : '/signin';
      }
      if (loc == '/signin') return _roleHome(auth.role);
      final role = auth.role;
      if (loc.startsWith('/admin') && role != UserRole.admin) return _roleHome(role);
      if (loc.startsWith('/driver') && role != UserRole.driver) return _roleHome(role);
      if ((loc == '/' || loc == '/trip' || loc == '/history') &&
          role != UserRole.passenger) {
        return _roleHome(role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (context, state) => const SignInPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const PassengerHomePage()),
          GoRoute(path: '/trip', builder: (c, s) => const PassengerTripPage()),
          GoRoute(path: '/history', builder: (c, s) => const PassengerHistoryPage()),
          GoRoute(path: '/driver', builder: (c, s) => const DriverHomePage()),
          GoRoute(path: '/driver/trip', builder: (c, s) => const DriverTripPage()),
          GoRoute(
              path: '/driver/earnings', builder: (c, s) => const DriverEarningsPage()),
          GoRoute(path: '/admin', builder: (c, s) => const AdminLivePage()),
          GoRoute(
              path: '/admin/verification',
              builder: (c, s) => const AdminVerificationPage()),
          GoRoute(path: '/admin/sos', builder: (c, s) => const AdminSosPage()),
          GoRoute(path: '/admin/fares', builder: (c, s) => const AdminFaresPage()),
          GoRoute(path: '/admin/reports', builder: (c, s) => const AdminReportsPage()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final offline = context.watch<OfflineQueue>();
    final role = auth.role;

    final destinations = <({String path, IconData icon, String label})>[
      if (role == UserRole.passenger) ...[
        (path: '/', icon: Icons.directions_car, label: 'Book'),
        (path: '/history', icon: Icons.history, label: 'History'),
      ],
      if (role == UserRole.driver) ...[
        (path: '/driver', icon: Icons.electric_rickshaw, label: 'Drive'),
        (path: '/driver/earnings', icon: Icons.payments, label: 'Earnings'),
      ],
      if (role == UserRole.admin) ...[
        (path: '/admin', icon: Icons.map, label: 'Live'),
        (path: '/admin/verification', icon: Icons.verified_user, label: 'Verify'),
        (path: '/admin/sos', icon: Icons.sos, label: 'SOS'),
        (path: '/admin/fares', icon: Icons.price_change, label: 'Fares'),
        (path: '/admin/reports', icon: Icons.assessment, label: 'Reports'),
      ],
    ];

    var index = destinations.indexWhere((d) => d.path == location);
    if (index < 0) index = 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text('SakayTa',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                role?.label ?? '',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await context.read<PresenceService>().goOffline();
              if (context.mounted) {
                await context.read<AuthController>().signOut();
              }
            },
            icon: const Icon(Icons.logout, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          if (offline.pending > 0)
            Container(
              width: double.infinity,
              color: AppTheme.fare100,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Text(
                '${offline.pending} saved action${offline.pending > 1 ? 's' : ''} waiting to send',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fare700),
              ),
            ),
          if (!AppConfig.isConfigured)
            const Padding(
              padding: EdgeInsets.all(8),
              child: ErrorBanner(
                'Supabase is not configured. Run with --dart-define-from-file=env.json',
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: destinations.isEmpty
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(destinations[i].path),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}
