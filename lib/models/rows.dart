import 'enums.dart';

DateTime? _dt(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
double? _dbl(dynamic value) =>
    value == null ? null : (value as num).toDouble();

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    this.phone,
  });

  final String id;
  final UserRole role;
  final String fullName;
  final String? phone;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        role: UserRole.fromDb(map['role'] as String),
        fullName: (map['full_name'] as String?) ?? '',
        phone: map['phone'] as String?,
      );
}

class Driver {
  const Driver({
    required this.id,
    required this.profileId,
    required this.status,
    this.licenseNo,
    this.idPhotoUrl,
    this.rating,
    this.ratingCount = 0,
    this.isOnline = false,
    this.lastLat,
    this.lastLng,
    this.createdAt,
    this.completedCount = 0,
    this.cancelledCount = 0,
  });

  final String id;
  final String profileId;
  final DriverStatus status;
  final String? licenseNo;
  final String? idPhotoUrl;
  final double? rating;
  final int ratingCount;
  final bool isOnline;
  final double? lastLat;
  final double? lastLng;
  final DateTime? createdAt;
  final int completedCount;
  final int cancelledCount;

  factory Driver.fromMap(Map<String, dynamic> map) => Driver(
        id: map['id'] as String,
        profileId: map['profile_id'] as String,
        status: DriverStatus.fromDb(map['status'] as String),
        licenseNo: map['license_no'] as String?,
        idPhotoUrl: map['id_photo_url'] as String?,
        rating: _dbl(map['rating']),
        ratingCount: (map['rating_count'] as num?)?.toInt() ?? 0,
        isOnline: (map['is_online'] as bool?) ?? false,
        lastLat: _dbl(map['last_lat']),
        lastLng: _dbl(map['last_lng']),
        createdAt: _dt(map['created_at']),
        completedCount: (map['completed_count'] as num?)?.toInt() ?? 0,
        cancelledCount: (map['cancelled_count'] as num?)?.toInt() ?? 0,
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.driverId,
    required this.type,
    this.plateNo,
    this.unitNo,
    this.franchiseNo,
    this.verified = false,
  });

  final String id;
  final String driverId;
  final VehicleType type;
  final String? plateNo;
  final String? unitNo;
  final String? franchiseNo;
  final bool verified;

  factory Vehicle.fromMap(Map<String, dynamic> map) => Vehicle(
        id: map['id'] as String,
        driverId: map['driver_id'] as String,
        type: VehicleType.fromDb(map['type'] as String),
        plateNo: map['plate_no'] as String?,
        unitNo: map['unit_no'] as String?,
        franchiseNo: map['franchise_no'] as String?,
        verified: (map['verified'] as bool?) ?? false,
      );
}

class FareZone {
  const FareZone({
    required this.id,
    required this.name,
    required this.centroidLat,
    required this.centroidLng,
  });

  final String id;
  final String name;
  final double centroidLat;
  final double centroidLng;

  factory FareZone.fromMap(Map<String, dynamic> map) => FareZone(
        id: map['id'] as String,
        name: map['name'] as String,
        centroidLat: (map['centroid_lat'] as num).toDouble(),
        centroidLng: (map['centroid_lng'] as num).toDouble(),
      );
}

class FareMatrixEntry {
  const FareMatrixEntry({
    required this.id,
    required this.originZone,
    required this.destZone,
    required this.vehicleType,
    required this.fare,
    this.isActive = true,
  });

  final String id;
  final String originZone;
  final String destZone;
  final VehicleType vehicleType;
  final double fare;
  final bool isActive;

  factory FareMatrixEntry.fromMap(Map<String, dynamic> map) => FareMatrixEntry(
        id: map['id'] as String,
        originZone: map['origin_zone'] as String,
        destZone: map['dest_zone'] as String,
        vehicleType: VehicleType.fromDb(map['vehicle_type'] as String),
        fare: (map['fare'] as num).toDouble(),
        isActive: (map['is_active'] as bool?) ?? true,
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.passengerId,
    required this.vehicleType,
    required this.fare,
    required this.status,
    required this.passengerCount,
    this.driverId,
    this.originZone,
    this.destZone,
    this.originLat,
    this.originLng,
    this.originLabel,
    this.destLat,
    this.destLng,
    this.destLabel,
    this.distanceKm,
    this.discountType,
    this.hasLuggage = false,
    this.paymentMethod = PaymentMethod.cash,
    this.requestedAt,
    this.assignedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.noShowAt,
    this.cancelReason,
  });

  final String id;
  final String passengerId;
  final String? driverId;
  final VehicleType vehicleType;
  final String? originZone;
  final String? destZone;
  final double? originLat;
  final double? originLng;
  final String? originLabel;
  final double? destLat;
  final double? destLng;
  final String? destLabel;
  final double? distanceKm;
  final double fare;
  final DiscountType? discountType;
  final int passengerCount;
  final bool hasLuggage;
  final BookingStatus status;
  final PaymentMethod paymentMethod;
  final DateTime? requestedAt;
  final DateTime? assignedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? noShowAt;
  final String? cancelReason;

  factory Booking.fromMap(Map<String, dynamic> map) => Booking(
        id: map['id'] as String,
        passengerId: map['passenger_id'] as String,
        driverId: map['driver_id'] as String?,
        vehicleType: VehicleType.fromDb(map['vehicle_type'] as String),
        originZone: map['origin_zone'] as String?,
        destZone: map['dest_zone'] as String?,
        originLat: _dbl(map['origin_lat']),
        originLng: _dbl(map['origin_lng']),
        originLabel: map['origin_label'] as String?,
        destLat: _dbl(map['dest_lat']),
        destLng: _dbl(map['dest_lng']),
        destLabel: map['dest_label'] as String?,
        distanceKm: _dbl(map['distance_km']),
        fare: (map['fare'] as num).toDouble(),
        discountType: DiscountType.fromDb(map['discount_type'] as String?),
        passengerCount: (map['passenger_count'] as num?)?.toInt() ?? 1,
        hasLuggage: (map['has_luggage'] as bool?) ?? false,
        status: BookingStatus.fromDb(map['status'] as String),
        paymentMethod: PaymentMethod.fromDb(map['payment_method'] as String),
        requestedAt: _dt(map['requested_at']),
        assignedAt: _dt(map['assigned_at']),
        arrivedAt: _dt(map['arrived_at']),
        startedAt: _dt(map['started_at']),
        completedAt: _dt(map['completed_at']),
        cancelledAt: _dt(map['cancelled_at']),
        noShowAt: _dt(map['no_show_at']),
        cancelReason: map['cancel_reason'] as String?,
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.commission,
    required this.driverNet,
    required this.status,
    required this.method,
  });

  final String id;
  final String bookingId;
  final double amount;
  final double commission;
  final double driverNet;
  final PaymentStatus status;
  final PaymentMethod method;

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as String,
        bookingId: map['booking_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        commission: (map['commission'] as num).toDouble(),
        driverNet: (map['driver_net'] as num).toDouble(),
        status: PaymentStatus.fromDb(map['status'] as String),
        method: PaymentMethod.fromDb(map['method'] as String),
      );
}

class SosAlert {
  const SosAlert({
    required this.id,
    required this.status,
    this.bookingId,
    this.triggeredBy,
    this.lat,
    this.lng,
    this.createdAt,
    this.acknowledgedAt,
    this.closedAt,
  });

  final String id;
  final String? bookingId;
  final String? triggeredBy;
  final double? lat;
  final double? lng;
  final SosStatus status;
  final DateTime? createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? closedAt;

  factory SosAlert.fromMap(Map<String, dynamic> map) => SosAlert(
        id: map['id'] as String,
        bookingId: map['booking_id'] as String?,
        triggeredBy: map['triggered_by'] as String?,
        lat: _dbl(map['lat']),
        lng: _dbl(map['lng']),
        status: SosStatus.fromDb(map['status'] as String),
        createdAt: _dt(map['created_at']),
        acknowledgedAt: _dt(map['acknowledged_at']),
        closedAt: _dt(map['closed_at']),
      );
}

class AppSettings {
  const AppSettings({
    this.baseFare = 15,
    this.perKmRate = 10,
    this.commissionRate = 0.10,
    this.discountRate = 0.20,
    this.fareMatrixIsPlaceholder = true,
  });

  final double baseFare;
  final double perKmRate;
  final double commissionRate;
  final double discountRate;
  final bool fareMatrixIsPlaceholder;

  factory AppSettings.fromRows(List<Map<String, dynamic>> rows) {
    double readNum(String key, double fallback) {
      for (final row in rows) {
        if (row['key'] == key) {
          final value = row['value'];
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? fallback;
        }
      }
      return fallback;
    }

    bool readBool(String key, bool fallback) {
      for (final row in rows) {
        if (row['key'] == key) return row['value'] == true;
      }
      return fallback;
    }

    return AppSettings(
      baseFare: readNum('base_fare', 15),
      perKmRate: readNum('per_km_rate', 10),
      commissionRate: readNum('commission_rate', 0.10),
      discountRate: readNum('discount_rate', 0.20),
      fareMatrixIsPlaceholder: readBool('fare_matrix_is_placeholder', true),
    );
  }
}

class NearbyDriver {
  const NearbyDriver({
    required this.driverId,
    required this.vehicleId,
    required this.distanceKm,
    this.plateNo,
    this.unitNo,
    this.rating,
  });

  final String driverId;
  final String vehicleId;
  final double distanceKm;
  final String? plateNo;
  final String? unitNo;
  final double? rating;

  factory NearbyDriver.fromMap(Map<String, dynamic> map) => NearbyDriver(
        driverId: map['driver_id'] as String,
        vehicleId: map['vehicle_id'] as String,
        distanceKm: (map['distance_km'] as num).toDouble(),
        plateNo: map['plate_no'] as String?,
        unitNo: map['unit_no'] as String?,
        rating: _dbl(map['rating']),
      );
}
