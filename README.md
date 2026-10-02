# SakayTa

Tricycle and tuk-tuk/bao-bao booking for Mati City, Davao Oriental. Flutter
client (Android + web) for passengers, drivers, and the admin/LGU desk, backed
by the same Supabase project as the web app.

Passengers see a fixed fare before booking and get an assigned driver. Drivers
stop doing tuyok-tuyok and receive ride requests instead. Both sides have a
hold-to-send SOS that logs the alert for the admin.

## What this talks to

The backend is unchanged from the web app: same Supabase project, same tables,
same RLS, same RPCs (`request_booking`, `accept_booking`, `transition_booking`,
`set_driver_presence`, `mark_payment`). Fares are computed server-side in
`quote_fare`; this client only previews them locally.

If you have not set up the backend yet, run the migration and seed in
`../mati-booking-app/supabase/` first.

## Setup

1. Install Flutter (stable) and the Android toolchain, then confirm:

   ```
   flutter doctor
   ```

2. Create `env.json` from the example and fill in your Supabase values:

   ```
   cp env.example.json env.json
   ```

   ```json
   {
     "SUPABASE_URL": "https://your-project-ref.supabase.co",
     "SUPABASE_ANON_KEY": "your-anon-public-key"
   }
   ```

   `env.json` is gitignored. These are compile-time values passed with
   `--dart-define-from-file`.

3. Fetch packages:

   ```
   flutter pub get
   ```

## Run and build

```
flutter run --dart-define-from-file=env.json
flutter build apk --debug --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

Regenerate branding assets after changing the logo:

```
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Tests and analysis

```
flutter analyze
flutter test
```

## Structure

```
lib/
  core/            config, theme, constants, formatting, geo, enums
  models/          row classes mirroring the Postgres schema
  data/            Api (RPC + realtime), auth, reference data, offline queue
  widgets/         shared UI, map, hold-to-send SOS button
  features/
    auth/
    passenger/
    driver/
    admin/
```

## Notes and limits in this MVP

- Cash only. Commission is recorded per trip; settlement is manual.
- Driver ID photos are a pasted link, not an upload.
- Zero-fare/zone data and fare rates are placeholder values marked `[VERIFY]`.
- Matching is broadcast: any verified, online driver of the matching vehicle
  type can accept; the first accept wins. Directed nearest-driver dispatch is a
  later phase.
- No push notifications yet. The driver app must be open to see new requests.
- SOS logs the alert; it does not dispatch responders or guarantee a response
  time. Who receives it must be confirmed with PNP Mati, MDRRMO, and 911.
- Android builds on this machine disable Kotlin incremental compilation
  (`android/gradle.properties`) because the incremental caches were locking.

## Before a real pilot

Confirm every `[VERIFY]` item in the web app's README: fare matrix and
ordinance, franchise records, whether "bao-bao" is the local term, terminal and
dispatcher rules, LTFRB/LTO/DILG classification, Data Privacy Act compliance
(NPC), BIR treatment of commissions, insurance, SOS routing, and signal
coverage. This is not legal advice.
