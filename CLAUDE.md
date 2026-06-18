# CLAUDE.md — Sawad Loan Universal

Flutter app for a Thai loan-application ("สมัครสินเชื่อ") flow. **Target is
Flutter web**, embedded inside a separate native Flutter app via
`flutter_inappwebview` (the native host launches this web build in a WebView).
Android/iOS/desktop scaffolding still exists but the web build is what ships.
**UI-only at this stage** — no backend/API wiring yet, and no Firebase SDK in
the app. Firebase is used **only for Hosting** (deploying the web build); there
are two projects, `prod` and `uat` (see Deploy below). Screens render from mock
data + a customer profile the host will provide. App language/data is **Thai**;
code comments are English.

## Current state (read this first)

- **No backend yet.** The wizard does not submit anywhere. The final "ถัดไป" on
  step 3 just shows a `SnackBar` ("ไปยังขั้นตอนถัดไป"). "บันทึกเตรียมข้อมูล"
  (save draft) buttons only show a confirmation `SnackBar` — nothing persists.
- **Mock data drives the UI.** `LoanRegisterForm.mock()` (matches "slide 7" of
  the design) seeds every field so screens render fully populated. Option lists
  (brands, models, provinces, installment counts, transfer types) are hardcoded
  `const` lists in the pages, not fetched.
- **Startup param:** the native host launches the web URL with
  `?hashThaiId=<...>`; `main.dart` reads it into `appState.hashThaiId`. The
  intended flow (TODO) is: fetch the customer profile by that hash, then
  `appState.setCustomerDetailFromJson(...)` so step 1 auto-fills.
- **OCR/camera is delegated to the native host** (the web build has no camera).
  Tapping ถ่ายรูปภาพ/OCR calls `NativeCameraBridge` which asks the host to open
  its camera; the host returns the photo as base64. There is a `TODO` in
  `collateral_info_page.dart` to then POST the image to an OCR API and auto-fill
  fields. OCR-target fields are marked in the UI with an `OcrBadge`.

## Run / quality commands

```sh
flutter pub get
flutter analyze --no-pub   # only pre-existing flutter_lints infos remain
flutter test               # smoke test (app boots to the list page) — green
flutter build web --release --pwa-strategy=none
```

- **Build web with `--pwa-strategy=none`** so the Flutter service worker doesn't
  serve a stale build inside the WebView (same lesson as the sibling pharmacy
  project). The host should also avoid aggressive caching of `index.html` /
  `main.dart.js`.
- The web build output is `build/web/`. It's deployed to **Firebase Hosting**
  (see Deploy below); the native host points its WebView at the hosted URL
  (append `?hashThaiId=<...>`).
- Android still declares the `CAMERA` permission but the `camera` plugin was
  removed; the host app owns the camera now.

## Deploy (Firebase Hosting — prod / uat)

Two separate Firebase projects, aliased in `.firebaserc` (`prod` / `uat`). The
active environment is baked in at build time via `--dart-define=ENV=prod|uat`
and read by `lib/config/app_environment.dart` (defaults to `uat` if unset).

A second define, `--dart-define=WEB_VERSION=<n>`, stamps the build version
(`kWebVersion`, defaults `'0'`). `main.dart` stores it on `AppState().webVersion`
and on **every** boot (release included) `print`s two console lines: a
human-readable `[SawadLoanUniversal] env=… webVersion=…`, and a machine-readable
`SawadLoanUniversalWebVersion:<n>`. CI passes the GitHub Actions run number, so
the version increments per deploy.

The native WebView host (`LoanUniversalWebWidget` in the srisawad app) parses
the `SawadLoanUniversalWebVersion:<n>` line and compares it to the latest
version from its `appConfig` (`sawad_loan_universal_version` /
`…_version_uat`); if the client is behind, it clears the WebView cache and
reloads once — so a **stale cached build** auto-refreshes. Bump that appConfig
value to match `WEB_VERSION` on each deploy, or the auto-reload never fires
(and never set it higher than what's actually deployed).

```sh
# build + deploy manually
flutter build web --release --pwa-strategy=none --dart-define=ENV=uat
firebase deploy --only hosting -P uat

flutter build web --release --pwa-strategy=none --dart-define=ENV=prod
firebase deploy --only hosting -P prod
```

- **CI/CD (GitHub Actions):** push to `main` → deploys **prod**; push to `uat`
  branch → deploys **uat** (`.github/workflows/deploy-prod.yml` /
  `deploy-uat.yml`). Both pin Flutter 3.38.5 and authenticate with the
  `FIREBASE_TOKEN` repo secret (`firebase login:ci`).
- `firebase.json` serves `build/web` as an SPA and sends `no-cache` for
  `index.html`, `flutter_bootstrap.js`, `main.dart.js`,
  `flutter_service_worker.js` so the WebView never serves a stale build.

## App structure (lib/)

- `main.dart` — `main()` calls `configureUrlStrategy()` (clean web URLs),
  builds the singleton `appState`, calls `initializePersistedState()`, reads
  `Uri.base.queryParameters['hashThaiId']` into `appState.hashThaiId`, then
  `runApp`. `MyApp` is a `MaterialApp.router` driven by `appRouter`
  (`router/app_router.dart`); the initial location `/` is `LoanRegisterListPage`.
- `router/app_router.dart` — **go_router** config + `AppRoutes` path constants.
  Each wizard page has its own URL (`/customerInfoPage`, `/collateralInfoPage`,
  `/loanInfoPage`, `/installmentPicker`, `/transferTypePicker`). Navigate with
  `context.push(AppRoutes.x, extra: form)`; pickers return their value via
  `context.pop(value)`. The mutable `LoanRegisterForm` is passed page→page as
  go_router `extra`; a fresh deep-link (no `extra`) falls back to the page's
  `.mock()` seed. `router/url_strategy.dart` is a conditional import
  (`usePathUrlStrategy()` on web, no-op off-web) — so URLs are
  `/customerInfoPage`, not `/#/...`. Firebase Hosting rewrites all paths to
  `index.html`, so deep links / refreshes resolve.
- `app_state.dart` — `AppState`, a `ChangeNotifier` **singleton**
  (`AppState()` always returns the same instance; `AppState.reset()` for
  tests). Persists one `CustomerDetail` to `SharedPreferences` under the key
  **`ff_customerDetail`** (the `ff_` prefix is a FlutterFlow carry-over).
  Read: `AppState().customerDetail`. Write via setter (auto-persists) or
  `update()/updateCustomerDetail()` (persist + `notifyListeners`).
- `models/customer_detail.dart` — plain-Dart model (no codegen) of the
  customer record an upstream API would return (snake_case JSON keys like
  `thai_id`, `first_name`, `is_existing_customer`, `consent`). Has
  `fromJson`/`toJson`/`copyWith` and **defensive coercion helpers**
  (`_asString`/`_asBool`/`_asDate`) so malformed API values never throw.

### Loan-register wizard (`lib/loan_register/`)

A 5-step flow (step indicator shows 1–5). Each page takes an optional
`LoanRegisterForm form`; if null it falls back to `.mock()` so any page can be
opened standalone (incl. via direct URL). The mutable form object is passed
page → page as go_router `extra` (see `router/app_router.dart`).

- `loan_register_list_page.dart` — entry: pick a product category
  (มอเตอร์ไซต์ / รายการเตรียมข้อมูล) → opens step 1. This is the app's home.
- `customer_info_page.dart` — **Step 1: ข้อมูลลูกค้า**. When opened from the
  menu (no form), seeds from `LoanRegisterForm.fromCustomerDetail(AppState().customerDetail)`
  — i.e. the persisted customer auto-fills step 1; steps 2–3 keep mock data.
  Editable name/phone/Thai-ID; bottom-sheet pickers for gender/nationality/
  occupation; date pickers; address cards + radio choice.
- `collateral_info_page.dart` — **Step 2: ข้อมูลหลักประกัน**. The ถ่ายรูปภาพ/OCR
  button calls `NativeCameraBridge.captureDocument('camera_collateral')`; the
  returned base64 is stored on `form.documentImageBase64` and shown as an
  uploaded-doc card (`Image.memory`, view-in-`InteractiveViewer`, delete).
  Dropdowns + autocomplete fields for vehicle details.
- `loan_info_page.dart` — **Step 3: ข้อมูลสินเชื่อ + ข้อมูลการโอนเงิน**. Mostly
  read-only calculated rows; opens the installment picker (step 4) and transfer
  type picker (step 5).
- `installment_picker_page.dart` / `transfer_type_picker_page.dart` — full-screen
  list selectors (steps 4 & 5); pop the chosen value back.
- `models/loan_register_form.dart` — the in-memory wizard model. `mock()` =
  fully-populated demo data; `fromCustomerDetail()` = seed step 1 from a real
  customer. Helpers: `_formatPhone`, `_formatThaiId`, `_formatBuddhistDate`
  (adds 543 unless year > 2200, i.e. already B.E.), `_genderFromTitle`,
  `_composeAddress`.

### Web ↔ native bridge (`lib/services/`)

- `native_bridge.dart` exports `NativeCameraBridge` via a conditional import:
  `native_bridge_web.dart` (real, web only) or `native_bridge_stub.dart`
  (throws `UnsupportedError` off-web, so the project still compiles for the VM /
  mobile / desktop and `flutter test` runs).
- **Contract — `flutter_inappwebview` JS handler (`callHandler`):**
  `captureDocument(action)` calls
  `window.flutter_inappwebview.callHandler('openCamera', action)` and awaits the
  returned Promise. The host registers `addJavaScriptHandler(handlerName:
  'openCamera', callback: ...)`, opens its camera for the `action` mask type
  (e.g. `collateral`, `idcard`), and **returns the photo as a base64 string**
  (raw or `data:` URL) — that value resolves the awaited `Future<Uint8List?>`.
  Returning `null`/`''` = cancelled (resolves with `null`, no error). Requests
  and responses are correlated automatically (no manual id matching).
  `isSupported` is false in a plain browser (no `window.flutter_inappwebview`).
- Compress the photo natively (≈1280px / JPEG ~80) before base64 so the bridge
  stays fast. The full handler code lives in the doc comment of
  `native_bridge.dart`.

### Reusable components (`lib/loan_register/components/`)

- `loan_register_styles.dart` — **single source of truth for colors/fonts.**
  Orange primary `#E8842A`, dark-blue value `#1B3A6B`, grey label `#9AA0A6`.
  Uses `google_fonts` NotoSansThai everywhere and `hexcolor`. Use these styles;
  don't hardcode new colors.
- `register_field_row.dart` — `RegisterFieldRow` (read-only/selector/date/
  calculated/OCR-filled row, auto-chevron when `onTap` set), plus `OcrBadge`
  and `RegisterSectionTitle` (orange bar header).
- `register_text_field.dart` — editable field styled to match the rows.
- `register_autocomplete_field.dart` — type-ahead text field (Flutter
  `Autocomplete`) for brand/model/detail.
- `address_card.dart` — `AddressCard` + `AddressRadioTile`.
- `register_step_indicator.dart` — the 1–5 step header.
- `save_next_bar.dart` — sticky bottom bar (outlined save-draft + solid next).

## Assets

`assets/` holds `MotorLoanIcon.svg`, `DocumentIcon.svg` (rendered via
`flutter_svg`). `pubspec.yaml` includes the whole `assets/` dir.

## Dependencies

`shared_preferences` (persist `CustomerDetail`), `google_fonts` (NotoSansThai),
`hexcolor`, `flutter_svg`, `web` (window/console bindings for the native
bridge). The `camera` plugin was **removed** — the host owns the camera. SDK
`^3.10.4` — code uses **Dart dot-shorthand syntax** (e.g.
`colorScheme: .fromSeed(...)`, `mainAxisAlignment: .center`); needs a recent
toolchain (built on Flutter 3.38 / Dart 3.10).

## Known quirks / gotchas

- `flutter analyze` reports ~19 **pre-existing `info` lints** (`use_super_parameters`,
  `withOpacity` deprecation, `unnecessary_underscores`) in the original screen
  code — no errors. Not introduced by the web conversion; clean up when
  convenient.
- Buddhist-era dates: the UI shows/expects B.E. `dd/MM/yyyy` (year = CE + 543).
  `_formatBuddhistDate` assumes a year > 2200 is already B.E. Today's "2569" =
  2026 CE.
- `CustomerDetail` JSON keys are **snake_case** (API contract); the Dart fields
  are camelCase — keep the `fromJson`/`toJson` mapping in sync when adding
  fields.
- Non-web targets: `NativeCameraBridge` is a stub that throws; the OCR button
  shows a "ใช้ได้เฉพาะในแอป" snackbar (guarded by `NativeCameraBridge.isSupported`).

## Conventions

- Thai UI strings inline; English code/comments.
- All styling goes through `LoanRegisterStyles` + `google_fonts` NotoSansThai.
- Build/verify with `flutter analyze --no-pub`, `flutter test`, and
  `flutter build web --release --pwa-strategy=none`. New model fields → update
  both `fromJson` and `toJson` (and `copyWith`).
