/// Enums mirroring the Postgres enums in the shared schema.
library;

enum UserRole {
  passenger('passenger', 'Passenger'),
  driver('driver', 'Driver'),
  admin('admin', 'Admin / LGU');

  const UserRole(this.db, this.label);
  final String db;
  final String label;

  static UserRole fromDb(String value) =>
      UserRole.values.firstWhere((e) => e.db == value, orElse: () => passenger);
}

enum VehicleType {
  tricycle('tricycle', 'Tricycle', 'Short trips, up to 3 passengers'),
  tuktuk('tuktuk', 'Tuk-tuk', 'Flat runs, more room for luggage'),
  baobao('baobao', 'Bao-bao', 'Local auto-rickshaw, same class as tuk-tuk');

  const VehicleType(this.db, this.label, this.hint);
  final String db;
  final String label;
  final String hint;

  static VehicleType fromDb(String value) => VehicleType.values
      .firstWhere((e) => e.db == value, orElse: () => tricycle);
}

enum DriverStatus {
  pending('pending', 'Pending'),
  verified('verified', 'Verified'),
  suspended('suspended', 'Suspended');

  const DriverStatus(this.db, this.label);
  final String db;
  final String label;

  static DriverStatus fromDb(String value) => DriverStatus.values
      .firstWhere((e) => e.db == value, orElse: () => pending);
}

enum BookingStatus {
  requested('requested', 'Looking for a driver'),
  assigned('assigned', 'Driver on the way'),
  arrived('arrived', 'Driver has arrived'),
  inProgress('in_progress', 'On the trip'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled'),
  noShow('no_show', 'No show'),
  expired('expired', 'Expired — no driver accepted');

  const BookingStatus(this.db, this.label);
  final String db;
  final String label;

  static BookingStatus fromDb(String value) => BookingStatus.values
      .firstWhere((e) => e.db == value, orElse: () => requested);

  bool get isActive => switch (this) {
        requested || assigned || arrived || inProgress => true,
        _ => false,
      };
}

enum PaymentMethod {
  cash('cash', 'Cash'),
  ewallet('ewallet', 'E-wallet');

  const PaymentMethod(this.db, this.label);
  final String db;
  final String label;

  static PaymentMethod fromDb(String value) => PaymentMethod.values
      .firstWhere((e) => e.db == value, orElse: () => cash);
}

enum PaymentStatus {
  pending('pending', 'Pending'),
  collected('collected', 'Collected'),
  settled('settled', 'Settled');

  const PaymentStatus(this.db, this.label);
  final String db;
  final String label;

  static PaymentStatus fromDb(String value) => PaymentStatus.values
      .firstWhere((e) => e.db == value, orElse: () => pending);
}

enum SosStatus {
  open('open', 'Open'),
  acknowledged('acknowledged', 'Acknowledged'),
  closedFalseAlarm('closed_false_alarm', 'Closed — false alarm'),
  closedResolved('closed_resolved', 'Closed — resolved');

  const SosStatus(this.db, this.label);
  final String db;
  final String label;

  static SosStatus fromDb(String value) => SosStatus.values
      .firstWhere((e) => e.db == value, orElse: () => open);
}

enum DiscountType {
  senior('senior', 'Senior citizen'),
  student('student', 'Student'),
  pwd('pwd', 'PWD');

  const DiscountType(this.db, this.label);
  final String db;
  final String label;

  static DiscountType? fromDb(String? value) {
    if (value == null) return null;
    for (final e in DiscountType.values) {
      if (e.db == value) return e;
    }
    return null;
  }
}
