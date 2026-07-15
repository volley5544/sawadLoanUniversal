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

- **No backend yet.** The wizard does not submit anywhere. It now runs all the
  way through **step 5** (ข้อมูลลูกค้า → หลักประกัน → สินเชื่อ → เอกสารแนบ/NDID →
  นัดหมายส่งเอกสาร); the final "ถัดไป" on step 5 just shows a `SnackBar`
  ("บันทึกข้อมูลเรียบร้อย"). "บันทึกเตรียมข้อมูล" (save draft) buttons only show a
  confirmation `SnackBar` — nothing persists. The NDID identity-verification
  hop is **real inside the native host, simulated in a plain browser**: when
  `NativeCameraBridge.isSupported` the NDID pages call the NDID local-node API
  (`lib/services/ndid_api.dart`, base URL `--dart-define=NDID_API_BASE`,
  default `https://dev.swpfin.com/dap`) — list IdPs → `POST /rp/verify` → poll
  status; otherwise the mock bank grid + "จำลองยืนยันตัวตนสำเร็จ" button remain
  (the bank's own app screens are third-party either way).
- **Mock data drives the UI.** `LoanRegisterForm.mock()` (matches "slide 7" of
  the design) seeds every field so screens render fully populated. Option lists
  (brands, models, provinces, installment counts, transfer types) are hardcoded
  `const` lists in the pages, not fetched.
- **Startup params:** the native host launches the web URL with
  `?hashThaiId=<...>&token=<firebase-jwt>` (both appended by the host's
  สมัครสินเชื่อ button / RouteGenerator). `main.dart` reads them into
  `appState.hashThaiId` / `appState.authToken`, then fires an **un-awaited**
  `_loadCustomerProfile()`: `UserApi.fetchUserDetail(hash)` →
  `appState.customerDetail` (persists + notifies) and
  `UserApi.fetchAddressBook(hash, token: …)` → `appState.customerAddressBook`
  (in-memory). While the fetch is in flight `AppState.profileLoading` is true
  (set/cleared around `_loadCustomerProfile`, only when a `hashThaiId` exists)
  and step 1 shows a blocking spinner overlay ("กำลังโหลดข้อมูลลูกค้า...") so
  the user can't edit fields the fetch is about to overwrite. Step 1
  auto-fills from these; if the fetch lands while step 1 is already open, the
  page re-seeds via an AppState listener (only when it owns its form, i.e.
  opened without `extra`). Fetch failures log to console and the UI keeps
  persisted/mock data.
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
  `/loanInfoPage`, `/installmentPicker`, `/transferTypePicker`,
  `/documentAttachPage`, `/documentReviewPage`, `/ndidBankSelectPage`,
  `/ndidVerifyPage`, `/appointmentPage`, `/documentsToPreparePage`). Navigate
  with `context.push(AppRoutes.x, extra: form)`; pickers and the NDID sub-flow
  return their value via `context.pop(value)` (the NDID flow pops `true`/`false`
  back up the chain so step 4 can flip to its verified state). The mutable `LoanRegisterForm` is passed page→page as
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
  occupation; date pickers; address cards + radio choice. While
  `AppState.profileLoading` is true (and the page owns its form) a
  semi-opaque loading overlay covers the page — it blocks input so the
  startup fetch can't overwrite half-typed edits, and disappears when the
  fetch lands (same listener that re-seeds the fields).
- `collateral_info_page.dart` — **Step 2: ข้อมูลหลักประกัน**. The ถ่ายรูปภาพ/OCR
  button calls `NativeCameraBridge.captureDocument('camera_collateral')`
  (falling back to the in-web `OcrCapturePage` camera mask in a plain browser);
  the returned base64 is stored on `form.documentImageBase64` and shown as an
  uploaded-doc card (`Image.memory`, view-in-`InteractiveViewer`, delete).
  Dropdowns + autocomplete fields for vehicle details.
- `loan_info_page.dart` — **Step 3: ข้อมูลสินเชื่อ + ข้อมูลการโอนเงิน**. Mostly
  read-only calculated rows; opens the installment + transfer-type sub-selectors.
  Its "ถัดไป" now pushes **step 4** (`documentAttach`, extra: form).
- `installment_picker_page.dart` / `transfer_type_picker_page.dart` — full-screen
  list **sub-selectors opened from step 3** (จำนวนงวด / ประเภทการโอน); pop the
  chosen value back. These are *not* wizard steps (the step indicator's 4 & 5 are
  the pages below).
- `document_attach_page.dart` — **Step 4: เอกสารแนบ** (slide 8 frame 1 + slide 9
  frame 1). Attach cards for บัตรประชาชน / เล่มทะเบียนรถ / เอกสารเพิ่มเติม (each
  captures via the `openCamera` bridge — actions `idcard` /
  `vehicle_registration` / `document` — falling back to `OcrCapturePage` in a
  plain browser; shows view/delete), plus a เอกสารประกอบสัญญา section
  whose ตรวจสอบเอกสาร row opens the NDID flow. On NDID success the card flips to
  a signed state (green check + ดาวน์โหลดเอกสาร) and the bottom "ถัดไป" unlocks →
  pushes step 5. Gated by `form.ndidVerified`.
- `document_review_page.dart` — **ตรวจสอบเอกสาร** (slide 8 frame 2). Contract-doc
  list + an acknowledge checkbox; the "ลงนามเอกสารและยืนยันตัวตน NDID" button
  starts the NDID flow and, on success, pops `true` back to step 4.
- `ndid_bank_select_page.dart` — **เลือกผู้ให้บริการ NDID** (slide 8 frames 3–4).
  Registered vs not-registered bank grids; ย้อนกลับ / ถัดไป. Inside the host the
  grids come from `NdidApi.listIdps()` (with the form's Thai ID → registered;
  full list minus those → not registered) with loading/retry states; a plain
  browser keeps the hardcoded mock banks. The picked IdP node id is stored on
  `form.ndidIdpId` and passed to the verify page.
- `ndid_verify_page.dart` — **ยืนยันตัวตน** countdown screen → **ยืนยันตัวตน
  สำเร็จ** (slide 8 frame 5 + final frame). One page, two phases. The bank's own
  app (K+ PIN pad, NDID consent) is **third-party — not rebuilt**. Inside the
  host it creates the real request (`NdidApi.createVerifyRequest`, 1 h
  `request_timeout` matching the countdown) and polls every 3 s; `ACCEPTED` →
  success phase, `REJECTED`/`TIMEOUT`/`CANCELLED` → error + ลองใหม่; ยกเลิก
  best-effort closes the request. In a plain browser a
  "จำลองยืนยันตัวตนสำเร็จ" button simulates the IDP callback. Pops `true`.
- `appointment_page.dart` — **Step 5: นัดหมายส่งเอกสาร** (slide 9 frame 2). The
  "เพิ่ม สาขาและวันที่-เวลานัดหมาย" card opens `documents_to_prepare_page`;
  "รายการนัดหมาย" shows the chosen appointment. "ถัดไป" ends the (UI-only) flow
  with a "บันทึกข้อมูลเรียบร้อย" SnackBar.
- `documents_to_prepare_page.dart` — **เอกสารที่ต้องเตรียมวันนัดหมาย** checklist
  (slide 9 frame 3). Its "ถัดไป" runs the branch → date/time picking flow, then
  pops the chosen `{branch, dateTime}` to the appointment list. **Branch pick is
  native-first:** inside the host it calls `NativeCameraBridge.pickBranch()`
  (`openBranchPicker` JS handler — the host's Google-Maps branch page owns GPS/
  nearby search and returns the chosen branch as JSON); in a plain browser it
  falls back to `branch_select_page.dart`.
- `branch_select_page.dart` — **ค้นหาสาขา** web fallback (slide 9 search frame):
  searchable mock-branch list + นัดหมาย button; pops the branch map (same shape
  as the bridge JSON). Only used when `NativeCameraBridge.isSupported` is false.
- `appointment_datetime_page.dart` — **วันที่-เวลา นัดหมาย** (slide 9 calendar
  frame): `CalendarDatePicker` + mock time slots (some ไม่ว่าง) + summary bar;
  บันทึกข้อมูล pops a Buddhist-era `dd/MM/yyyy HH:mm น.` string.
- `models/loan_register_form.dart` — the in-memory wizard model. `mock()` =
  fully-populated demo data; `fromCustomerDetail()` = seed step 1 from a real
  customer. Address seeding: the address-book API is **authoritative per
  address type** — a loaded-but-empty block renders blank (`''`, the
  `AddressCard` shows no placeholder text); the profile's single composed
  address is only the fallback when the address book is missing entirely
  (fetch failed / still loading). Helpers: `_formatPhone`, `_formatThaiId`, `_formatBuddhistDate`
  (adds 543 unless year > 2200, i.e. already B.E.), `_genderFromTitle`,
  `_composeAddress`. Step-4/5 fields: `ndidVerified` (bool, gates step 4's
  "ถัดไป"), `appointmentBranch`, `appointmentDateTime`. Attached document bytes
  on step 4 are held in page state only (not on the form). When adding fields
  here, also seed them in `mock()`.

### Mobile API client (`lib/services/user_api.dart`)

`UserApi` — client for the srisawad **mobile API** (`api_data/api1.md`,
untracked): `fetchUserDetail(hash)` (`GET /user/detail?hash_thai_id=…`, payload
under `results` with its own `code`/`message` — non-200 code throws) and
`fetchAddressBook(hash, token: …)` (`GET /profile/address/{hash}`, needs the
`Authorization: Bearer` token from the `?token=` launch param). Base URL +
`x-srisawad` header are per-environment on `AppEnvironment`
(prod `https://mobile-api.swpfin.com` + `x-srisawad: x1`;
uat `https://dev.swpfin.com:7076`, no header). Errors throw
`UserApiException`. Models: `models/customer_detail.dart` (profile) and
`models/customer_address.dart` (`AddressInfo` ×4 + `data_date`;
`AddressInfo.oneLine` renders the display string used on step 1 — id_card →
idCardAddress, current → currentAddress, other → workAddress).

### API transport (`lib/services/api_transport.dart`)

`sendApiRequest(method, url, headers, body)` — shared GET/POST plumbing for
`NdidApi` + `UserApi`: inside the native host every request goes through the
host's `httpRequest` JS bridge handler (native HTTP, no CORS; the host
allowlists the NDID gateway + mobile API bases), in a plain browser it falls
back to package:http (works only for CORS-enabled endpoints — the mobile API
sends `access-control-allow-origin: *`, the NDID gateway does not). Network
failures throw `ApiTransportException`.

### NDID API client (`lib/services/ndid_api.dart`)

`NdidApi` — static `http` client for the **NDID local-node API** (the
`localhost:7088` wrapper; Postman collection + proxy spec live in the
untracked `ndid_doc/` folder). Only the RP-role endpoints the flow needs:
`listIdps()` (`POST /idp/list`), `createVerifyRequest()` (`POST /rp/verify`,
mode 2 / min_ial 1.1 / min_aal 1 / "Authen Only"), `getVerifyStatus()`
(`GET /rp/verify/{referenceId}`, status `CREATED|PENDING|ACCEPTED|REJECTED|
TIMEOUT|CANCELLED`), `closeVerifyRequest()` (best-effort cancel). Errors throw
`NdidApiException` (parses the node's `{status, message}` error body).
**Transport:** the gateway sends no CORS headers (and 401s preflights), so a
browser fetch is blocked — inside the host every request goes through the
host's `httpRequest` JS bridge handler (native HTTP, allowlisted to the NDID
gateway; contract in `native_bridge.dart`'s doc comment, implementation in the
srisawad app's `loan_universal_web_widget.dart`); plain `http` is only the
plain-browser/dev fallback. The
node manages its own NDID token; client auth is an `X-API-Key` header
(`kNdidApiKey`, `--dart-define=NDID_API_KEY`, has a baked-in default — note a
web build can't keep it secret from clients anyway). Base URL: `kNdidApiBase` in
`app_environment.dart` (`--dart-define=NDID_API_BASE`, default
`https://dev.swpfin.com/dap`; point it at `http://localhost:7088` to hit a
locally-run node — an `http:` URL additionally needs the WebView to allow
mixed content when the app is served over `https:`).

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
- **`openBranchPicker` handler:** `pickBranch()` asks the host to open its
  branch-picker map (step-5 appointment). The host pushes a selection-mode map
  page and returns the chosen branch as a **JSON string** (`branchName`,
  `address`, `phone`, `lat`, `lng`); `null`/`''` = cancelled. Handler snippet
  also in `native_bridge.dart`'s doc comment.

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
bridge), `http` (NDID local-node API client). The `camera` plugin was **removed** — the host owns the camera. SDK
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
