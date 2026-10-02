import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/geo.dart';
import '../models/enums.dart';
import '../models/rows.dart';

/// Thin wrapper over the shared Supabase backend.
///
/// All fare calculation, booking transitions, and payments happen server-side
/// through RPCs, exactly as in the web app. This class does not reimplement any
/// business rules.
class Api {
  SupabaseClient get _c => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  User? get currentUser => _c.auth.currentUser;
  Session? get currentSession => _c.auth.currentSession;

  Future<AuthResponse> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email.trim(), password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
  }) =>
      _c.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          // Only passenger and driver are self-selectable; admin is set in the DB.
          'role': role == UserRole.driver ? 'driver' : 'passenger',
        },
      );

  Future<void> signOut() => _c.auth.signOut();

  Stream<AuthState> get authStateChanges => _c.auth.onAuthStateChange;

  Future<Profile?> fetchProfile(String userId) async {
    final data =
        await _c.from('profiles').select().eq('id', userId).maybeSingle();
    return data == null ? null : Profile.fromMap(data);
  }

  Future<Driver?> fetchDriver(String userId) async {
    final data = await _c
        .from('drivers')
        .select()
        .eq('profile_id', userId)
        .maybeSingle();
    return data == null ? null : Driver.fromMap(data);
  }

  Future<Vehicle?> fetchVehicle(String driverId) async {
    final data = await _c
        .from('vehicles')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data == null ? null : Vehicle.fromMap(data);
  }

  // ---------------------------------------------------------------------------
  // Reference data
  // ---------------------------------------------------------------------------

  Future<AppSettings> fetchSettings() async {
    final rows = await _c.from('app_settings').select();
    return AppSettings.fromRows(List<Map<String, dynamic>>.from(rows));
  }

  Future<List<FareZone>> fetchZones() async {
    final rows =
        await _c.from('fare_zones').select().eq('is_active', true).order('name');
    return rows.map((r) => FareZone.fromMap(r)).toList();
  }

  Future<List<FareMatrixEntry>> fetchMatrix() async {
    final rows = await _c.from('fare_matrix').select().eq('is_active', true);
    return rows.map((r) => FareMatrixEntry.fromMap(r)).toList();
  }

  Future<double> quoteFare({
    required VehicleType vehicleType,
    String? originZone,
    String? destZone,
    double? originLat,
    double? originLng,
    double? destLat,
    double? destLng,
    DiscountType? discount,
  }) async {
    final result = await _c.rpc('public_quote', params: {
      'p_vehicle_type': vehicleType.db,
      'p_origin_zone': originZone,
      'p_dest_zone': destZone,
      'p_origin_lat': originLat,
      'p_origin_lng': originLng,
      'p_dest_lat': destLat,
      'p_dest_lng': destLng,
      'p_discount_type': discount?.db,
    });
    return (result as num).toDouble();
  }

  Future<List<NearbyDriver>> findNearbyDrivers({
    required LatLng at,
    required VehicleType vehicleType,
    int limit = 5,
  }) async {
    final result = await _c.rpc('find_nearby_drivers', params: {
      'p_lat': at.lat,
      'p_lng': at.lng,
      'p_vehicle_type': vehicleType.db,
      'p_limit': limit,
    });
    return (result as List)
        .map((r) => NearbyDriver.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Bookings
  // ---------------------------------------------------------------------------

  Future<Booking> requestBooking({
    required VehicleType vehicleType,
    required String originZone,
    required String destZone,
    double? originLat,
    double? originLng,
    String? originLabel,
    double? destLat,
    double? destLng,
    String? destLabel,
    DiscountType? discount,
    int passengerCount = 1,
    bool hasLuggage = false,
  }) async {
    final result = await _c.rpc('request_booking', params: {
      'p_vehicle_type': vehicleType.db,
      'p_origin_zone': originZone,
      'p_dest_zone': destZone,
      'p_origin_lat': originLat,
      'p_origin_lng': originLng,
      'p_origin_label': originLabel,
      'p_dest_lat': destLat,
      'p_dest_lng': destLng,
      'p_dest_label': destLabel,
      'p_discount_type': discount?.db,
      'p_passenger_count': passengerCount,
      'p_has_luggage': hasLuggage,
    });
    return Booking.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<Booking> acceptBooking(String bookingId) async {
    final result = await _c.rpc('accept_booking', params: {
      'p_booking_id': bookingId,
    });
    return Booking.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<Booking> transition(
    String bookingId,
    BookingStatus to, {
    String? note,
  }) async {
    final result = await _c.rpc('transition_booking', params: {
      'p_booking_id': bookingId,
      'p_to': to.db,
      'p_note': note,
    });
    return Booking.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<void> setPresence({required bool online, LatLng? at}) =>
      _c.rpc('set_driver_presence', params: {
        'p_is_online': online,
        'p_lat': at?.lat,
        'p_lng': at?.lng,
      });

  Future<void> markPayment(String bookingId, PaymentStatus status) =>
      _c.rpc('mark_payment', params: {
        'p_booking_id': bookingId,
        'p_status': status.db,
      });

  Future<Payment?> fetchPayment(String bookingId) async {
    final data = await _c
        .from('payments')
        .select()
        .eq('booking_id', bookingId)
        .maybeSingle();
    return data == null ? null : Payment.fromMap(data);
  }

  Future<List<Payment>> fetchPaymentsForBookings(List<String> bookingIds) async {
    if (bookingIds.isEmpty) return const [];
    final rows = await _c
        .from('payments')
        .select()
        .inFilter('booking_id', bookingIds);
    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  Future<void> insertRating({
    required String bookingId,
    required UserRole raterRole,
    required String raterId,
    required int stars,
    String? comment,
  }) =>
      _c.from('ratings').insert({
        'booking_id': bookingId,
        'rater_role': raterRole.db,
        'rater_id': raterId,
        'stars': stars,
        'comment': comment,
      });

  Future<void> insertSos({
    required String bookingId,
    required String triggeredBy,
    LatLng? at,
  }) =>
      _c.from('sos_alerts').insert({
        'booking_id': bookingId,
        'triggered_by': triggeredBy,
        'lat': at?.lat,
        'lng': at?.lng,
        'status': 'open',
      });

  // ---------------------------------------------------------------------------
  // Streams (realtime, RLS-scoped)
  // ---------------------------------------------------------------------------

  Stream<List<Booking>> bookingsForPassenger(String passengerId) => _c
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('passenger_id', passengerId)
      .order('requested_at')
      .map((rows) => rows.map((r) => Booking.fromMap(r)).toList());

  Stream<List<Booking>> bookingsForDriver(String driverId) => _c
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('driver_id', driverId)
      .order('requested_at')
      .map((rows) => rows.map((r) => Booking.fromMap(r)).toList());

  Stream<List<Booking>> openRequests(VehicleType vehicleType) => _c
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('status', 'requested')
      .eq('vehicle_type', vehicleType.db)
      .order('requested_at')
      .map((rows) => rows.map((r) => Booking.fromMap(r)).toList());

  Stream<List<Booking>> allActiveBookings() => _c
      .from('bookings')
      .stream(primaryKey: ['id'])
      .order('requested_at')
      .map((rows) => rows
          .map((r) => Booking.fromMap(r))
          .where((b) => b.status.isActive)
          .toList());

  Stream<List<Driver>> onlineDrivers() => _c
      .from('drivers')
      .stream(primaryKey: ['id'])
      .eq('is_online', true)
      .map((rows) => rows.map((r) => Driver.fromMap(r)).toList());

  /// Live position of one driver (used for passenger tracking).
  Stream<Driver?> driverById(String driverId) => _c
      .from('drivers')
      .stream(primaryKey: ['id'])
      .eq('id', driverId)
      .map((rows) => rows.isEmpty ? null : Driver.fromMap(rows.first));

  /// Real road route + ETA via the `route` edge function (OpenRouteService).
  Future<RouteResult?> getRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final res = await _c.functions.invoke('route', body: {
      'from': [from.lng, from.lat],
      'to': [to.lng, to.lat],
    });
    final data = res.data;
    if (data is Map) {
      return RouteResult.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Photos (private bucket 'driver-photos', path = {profileId}/{kind}.{ext})
  // ---------------------------------------------------------------------------

  Future<String> uploadPhoto({
    required String profileId,
    required String kind,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    final path = '$profileId/$kind.$ext';
    await _c.storage.from('driver-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return path;
  }

  Future<String?> signedPhotoUrl(String? path, {int expiresIn = 3600}) async {
    if (path == null || path.isEmpty) return null;
    // Already a full URL (e.g. legacy pasted link) — return as-is.
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return await _c.storage.from('driver-photos').createSignedUrl(path, expiresIn);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Mock wallet + simulated e-wallet payments
  // ---------------------------------------------------------------------------

  Stream<double> walletBalance(String profileId) => _c
      .from('wallets')
      .stream(primaryKey: ['profile_id'])
      .eq('profile_id', profileId)
      .map((rows) =>
          rows.isEmpty ? 0.0 : (rows.first['balance'] as num).toDouble());

  Future<double> walletTopup(double amount) async {
    final result = await _c.rpc('wallet_topup', params: {'p_amount': amount});
    return (result as num).toDouble();
  }

  Future<void> walletPayBooking(String bookingId) =>
      _c.rpc('wallet_pay_booking', params: {'p_booking_id': bookingId});

  Future<void> mockEwalletPay(String bookingId, String provider) =>
      _c.rpc('mock_ewallet_pay', params: {
        'p_booking_id': bookingId,
        'p_provider': provider,
      });

  Stream<List<Map<String, dynamic>>> walletTransactions(String profileId) => _c
      .from('wallet_transactions')
      .stream(primaryKey: ['id'])
      .eq('profile_id', profileId)
      .order('created_at')
      .map((rows) => rows.reversed.toList());

  Stream<List<SosAlert>> sosAlerts() => _c
      .from('sos_alerts')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map((r) => SosAlert.fromMap(r)).toList());

  Stream<List<Profile>> profilesByIds(List<String> ids) {
    if (ids.isEmpty) return const Stream.empty();
    return _c
        .from('profiles')
        .stream(primaryKey: ['id'])
        .inFilter('id', ids)
        .map((rows) => rows.map((r) => Profile.fromMap(r)).toList());
  }

  // ---------------------------------------------------------------------------
  // Fetches for booking details
  // ---------------------------------------------------------------------------

  Future<Booking?> fetchBooking(String bookingId) async {
    final data =
        await _c.from('bookings').select().eq('id', bookingId).maybeSingle();
    return data == null ? null : Booking.fromMap(data);
  }

  Future<List<Booking>> fetchCompletedBookings({int limit = 200}) async {
    final rows = await _c
        .from('bookings')
        .select()
        .eq('status', 'completed')
        .order('completed_at', ascending: false)
        .limit(limit);
    return rows.map((r) => Booking.fromMap(r)).toList();
  }

  Future<Driver?> fetchDriverById(String driverId) async {
    final data =
        await _c.from('drivers').select().eq('id', driverId).maybeSingle();
    return data == null ? null : Driver.fromMap(data);
  }
}
