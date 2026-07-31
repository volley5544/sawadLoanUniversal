# CLAUDE.md — Sawad Loan Universal

Flutter app for a Thai loan-application ("สมัครสินเชื่อ") flow. **Target is
Flutter web**, embedded inside a separate native Flutter app via
`flutter_inappwebview` (the native host launches this web build in a WebView).
Android/iOS/desktop scaffolding still exists but the web build is what ships.
App language/data is **Thai**; code comments are English.

**Two features, at very different stages** — this is the thing to get straight
before changing anything:

| | 5-step loan-register wizard (`lib/loan_register/`) | P-Loan application (`lib/p_loan/application/`) |
| --- | --- | --- |
| State | **UI-only.** Renders from `LoanRegisterForm.mock()` | **Live end to end**, no mock fallback |
| Submits | nowhere — final ถัดไป is a SnackBar | `POST /topup` (Extra) / `POST /SavePloanContract` (new) |
| Reads | a customer profile + address book | `/user/detail`, `/loan/list`, `/topup/*`, `/pdf/loan`, `/vision/thai-id-validate` |

There is still **no Firebase SDK** in the app — but Firebase is no longer only
Hosting: the uat project also serves a runtime-config document over the
**Firestore REST API**, read with an **anonymous Auth** token minted over REST
(`services/firebase_auth_rest.dart`, `services/app_config_api.dart`). Two
projects, `prod` and `uat` (see Deploy below).

## Current state (read this first)

- **The P-Loan application flow is the live one.** Its screens have no mock
  fallback (fixtures exist behind a default-off define — see **Mock mode**). Both
  products post to a real endpoint, but only the **Extra** path can currently
  complete. A **new P-Loan** is blocked on **two** things, both because that
  product has **no contract** (see *A new P-Loan has no contract at all*):
  `POST /pdf/loan` can't produce the documents its submit gate needs, and the
  save endpoint needs a native-host handler that does not exist yet (see
  **Outstanding** #2). It also **prices steps 2–3 with an interim client-side
  estimate** — no calculator API yet, and the top-up one can't stand in (see
  **New-P-Loan pricing (interim)**).
- **The P-Loan Extra has two entry points.** The home menu runs all six steps.
  The **LandAndHouseWeb top-up card** deep-links to `/pLoan/resume`, which
  rebuilds the flow and runs only **3 → 5 → 6** (see **Two entry points**).
  That path needs a matching change in *two other repos* — the host app
  (**done**, see below) and LandAndHouseWeb (**owned by the user**, snippet in
  **What LandAndHouseWeb has to do**).
  Everything below in this list is about the **wizard**, which is still UI-only.
- **The wizard has no backend.** It does not submit anywhere. It now runs all the
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
flutter test               # 115 tests (models, payloads, mock-mode guard) — green
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

### Auto-deploy to uat (`tools/deploy-uat.sh`)

⚠ **The `Stop` hook this section used to describe is no longer configured.**
`.claude/settings.local.json` currently holds a `permissions` block and nothing
else — no `hooks` key — so finishing a turn deploys **nothing**. Verified
2026-07-31. What actually ships uat today is **CI**: any push to the `uat` branch
runs `.github/workflows/deploy-uat.yml`, which is why the deployed `WEB_VERSION`
tracks the GitHub Actions **run number** rather than this script's counter. Run
`tools/deploy-uat.sh [--force]` by hand when you want a deploy without a push.

If the hook is restored, note it was deliberately **not** a
`PostToolUse`/`Write|Edit` hook: that fires after every single edit and would
push dozens of half-finished refactors per task.

Two consequences of CI owning the deploy, both seen on 2026-07-31:

- **Rapid consecutive pushes cancel each other.** Runs #49 and #50 were 23 s
  apart; #49 was cancelled and only #50 (the branch tip) shipped. Harmless when
  the later commit is a superset, which it was — but "cancelled" in the run list
  is not a failure to chase.
- The version stamp jumps to whatever the run number is, so `WEB_VERSION` is not
  contiguous with what `.deploy-version-uat` last recorded.

The script declines to deploy when:

- **nothing changed** — it fingerprints `lib/`, `web/`, `assets/`,
  `pubspec.yaml` and `pubspec.lock` against `.deploy-stamp-uat`, so a docs- or
  test-only turn is a silent no-op;
- **`flutter analyze` reports an error or warning** — it never ships a build
  that doesn't compile, and reports the first message instead.

`WEB_VERSION` is derived from the version **actually live** on the site (+1)
rather than a local counter, so a CI deploy in between can't make it go
backwards. The stamp is only written after a successful deploy, so a failure
retries on the next turn. Both stamp files are git-ignored.

**Still manual:** bumping `sawad_loan_universal_version_uat` in the host's
appConfig to match. Until that is raised, the host's stale-cache auto-reload
won't fire for the new build.

### appConfig Firestore importer (`tools/firestore-import/`)

Beyond Hosting, the **uat** project (`sawad-loan-universal-uat`) now also holds
the appConfig document **`application/config`** — the same shape as the srisawad
mobile app's, including `sawad_loan_universal_version` /
`…_version_uat`. It was seeded on 2026-07-27 from the dump in
`etc/firestore_clone_data.txt`.

`tools/firestore-import/import-config.mjs` parses those console-export dumps
(`<field>` / `<value>` / `(<type>)` records, brace-delimited `(map)`,
index-keyed `(array)`) into Firestore REST typed values and PATCHes them to a
project. **One tap:** double-click `import-uat-config.bat` in the repo root.

```sh
node tools/firestore-import/import-config.mjs --dry-run   # preview only
node tools/firestore-import/import-config.mjs             # write to the uat alias
```

- Zero npm deps (Node 20 `fetch`); auth reuses the **Firebase CLI login** —
  it reads the CLI's `cloud-platform`-scoped access token from
  `~/.config/configstore/firebase-tools.json` and shells out to `firebase
  projects:list` to refresh it when near expiry, so no service-account key is
  needed. `firebase login` is the only prerequisite.
- Defaults to the `uat` alias in `.firebaserc`; **refuses prod-looking project
  ids** unless `--allow-prod`. Backs the existing document up to `etc/backup/`
  before writing, replaces by default (`--merge` to keep unlisted fields), and
  reads back to verify. Unknown `(type)` markers are a hard error, never a
  guess.
- `etc/*.txt` and `etc/backup/` are **git-ignored** — the dumps contain live
  `agent_web_api_token*` values.
- **`application/config` is the private one.** It holds the
  `agent_web_api_token*` values, and `firestore.rules` grants no client any
  access to it (verified: an anonymous `GET` returns **403**). The app reads
  `application/public_config` instead — see **Runtime config from Firestore**.
- Its `sawad_loan_universal_version_uat` field is **vestigial**, left over from
  the seeded dump. The host's stale-build check reads the *srisawad* project's
  appConfig, not this copy, so don't chase this number when a client looks
  stale.

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
  **P-Loan routes are stricter:** that flow has no mock seed, so steps 2–6
  redirect to step 1 without an `extra`. The two URL-addressable P-Loan entry
  points are `/pLoan/contract` (step 1) and `/pLoan/resume` (the top-up-card
  deep link, which builds its own flow from query params — see **Two entry
  points**).
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
  (มอเตอร์ไซต์ / รายการเตรียมข้อมูล) → opens step 1, or **สมัครสินเชื่อ P-Loan**
  → opens the standalone P-Loan form (see below). This is the app's home.
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
  **Shared with the P-Loan flow's step 6.** It and `ndid_verify_page` take a
  `NdidSubject` (`models/ndid_subject.dart`) rather than a `LoanRegisterForm`:
  they only ever needed the Thai ID and the picked IdP id, so `LoanRegisterForm`
  and `PLoanFlow` both implement that interface instead of the pages being
  duplicated. `ndidThaiId` is digits-only — the wizard holds it formatted for
  display, and each implementation strips its own.
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

### P-Loan (`lib/p_loan/`) — two separate features

`lib/p_loan/` holds **two unrelated things**, both ported from the FlutterFlow
project at `D:\FlutterProject\land_and_house_web_new`. Don't confuse them:

| | `submit_form/` | `application/` |
| --- | --- | --- |
| What | Internal 34-field data-entry form | Customer-facing 6-step wizard |
| Source folder | its `lib/p_loan_form_page/` | its `lib/p_loan/` |
| Submits to | `regmast_ploan.php` (internal IP) | `POST /topup` (Extra) / `POST /SavePloanContract` (new) |
| Home-menu card | สมัครสินเชื่อ P-Loan | ขอสินเชื่อส่วนบุคคล |
| Data | Sample/mock values | Live API, no mock fallback |

### P-Loan application flow (`lib/p_loan/application/`)

A **6-step wizard**: เลือกสัญญา → ยอดจัดสินเชื่อ → จำนวนงวด →
รูปภาพหลักประกัน → ตรวจสอบข้อมูลส่วนตัว → สรุป/ยืนยัน, then a success screen.
Entry point `AppRoutes.pLoanContractSelect` (`/pLoan/contract`). Step 6 ends
with an NDID signing hop reusing the wizard's screens — see **Step 6** below.

#### Two entry points (`PLoanEntry`)

The six screens are reachable two ways. `PLoanEntry` is set once at
construction and decides **which of them a run visits**; only two places branch
on it (step 3's Next target and the step indicator).

| | `PLoanEntry.wizard` | `PLoanEntry.topupCard` |
| --- | --- | --- |
| Entered at | step 1 (`/pLoan/contract`) | **step 3**, via `/pLoan/resume` |
| From | this app's home menu | **two triggers** — see below |
| Visits | 1 → 2 → 3 → 4 → 5 → 6 | **3 → 5 → 6** |
| Indicator | 1/6 … 6/6 | renumbered **2/4, 3/4, 4/4** — the card is step 1 |
| Back on the first screen | normal pop | `closeWebview` → back to the top-up card |
| Kind | either | always Extra |

**Why steps 2 and 4 are skipped** (the requirement, not an optimisation): the
top-up card already showed the customer the approved amount, and an Extra's
collateral is already on file from `/loan/list`.

**Why the indicator starts at 2, not 1** (`PLoanEntry.precedingSteps`). The
customer's journey begins on the LandAndHouseWeb top-up card — that is where
they pick the contract and see the amount, which is the work the wizard's steps
1–2 do. Opening this build at "1 of 3" presented it as a separate application
and disowned the screen they just came from, so `topupCard` declares
`precedingSteps: 1`: `totalSteps` becomes 4 and every `stepNumber` shifts up
one. Circle 1 renders filled (the indicator fills every step `<= currentStep`),
so it reads as already done. Nothing but the enum changed — all five screens
already ask the flow for their number.

⚠ **Skipping step 4 means no collateral photos are submitted** —
`carImage`/`documentImage` are empty and `property_image`/`act_image` go out as
`''`. `test/p_loan_flow_test.dart` pins that this cannot deadlock `canSubmit`
(which gates on the *identity* photos only). If the backend rejects a top-up
with no vehicle shots, this is the reason.

**`p_loan_topup_card_resume_page.dart`** (`/pLoan/resume?dbName=&contractNo=`,
optional `&amount=`) is the entry screen. Steps 2–6 carry the mutable
`PLoanFlow` in go_router `extra`, so a URL cannot enter mid-flow — instead of
serialising that object into the query string, this route **re-runs the same
calls step 2 makes** from the minimal `db_name` + `contract_no` key, then
`pushReplacement`s to step 3. Consequences worth keeping:

- a refresh reproduces the state rather than resuming a stale copy;
- it re-checks the three preconditions step 1 checks (`isSelectable`,
  `hasNoRequestYet`, `isEligible`) because it bypasses that screen;
- the requested amount is `LoanAmountDetail.extraRequestAmount` — **`topup_extra`
  exactly** — reached via `topupCardRequestAmount`, which only adds the
  `?amount=` override. Step 2 reads the same getter, so the menu path and the
  deep link cannot quote different amounts for one contract;
- **`0` means no offer** and is reported as such rather than requested. There is
  no fallback to `default_topup_amount` and no range check — see
  **P-Loan Extra's amount is not the top-up amount** below.

**`/pLoan/resume` has two triggers, one `PLoanEntry`.** Both push the same route
with the same `{dbName, contractNo}` and no `amount`, so the flow cannot tell
them apart — and doesn't need to:

| Trigger | Where | How |
| --- | --- | --- |
| LandAndHouseWeb top-up card's **สินเชื่อเพิ่ม** | inside a WebView, so it can't reach native directly | `window.location.href = 'srisawad://ploan-extra?…'`, intercepted by the host |
| The srisawad app's home **LoanCard** → สิทธิพิเศษเฉพาะคุณ chip with `product_code == 'PLD001'` | native | `Navigator.pushNamed('/loan-universal-webview', …)` directly — no custom scheme needed |

The second was added 2026-07-30 (`lib/widgets/loan_card.dart` in the host repo).
It deliberately **skips the host's `/consent` route**, which every other chip in
that section takes: those pages book a *top-up* of the contract, and a P-Loan
Extra only references it.

**Native host side** (in the srisawad app):

- `video_record_web_widget.dart` — the widget hosting LandAndHouseWeb —
  intercepts `srisawad://ploan-extra?dbName=&contractNo=&amount=` in
  `shouldOverrideUrlLoading`, cancels the navigation and pushes
  `/loan-universal-webview` with `path: '/pLoan/resume'` + those params. It
  reads the Firebase `userToken` from local storage through its own
  `LocalStoragePrefernces()` instance (that file doesn't import the
  `localStorageObject` global) — the same token source as the home menu's
  สมัครสินเชื่อ button, so both entry points authenticate identically.
- `routegenerator.dart`'s `/loan-universal-webview` gained `path` + `params`
  args and now merges the URL **through `Uri`** instead of concatenating
  `'$base/?hashThaiId=…'`, which corrupted any override that already had a
  query.
- ⚠ It must **not** go through the generic `/webview-page`: that renders
  `VideoRecordWebWidget`, which registers none of this build's JS handlers. Our
  `NativeCameraBridge.isSupported` is just `window.flutter_inappwebview != null`
  — true in *any* InAppWebView — so we would route every API call to a
  `httpRequest` handler that isn't there and fail on every screen.

Both host edits are committed on `main` in
`D:\FlutterProject\srisawad_mobile_app_flutter3.38.5\srisawad_mobile_app_flutter3.38.5`
(GitLab `internal/srisawad_mobile_app_flutter3.38.5`), and documented in that
repo's own CLAUDE.md (*Routing* + *Behavior notes*) and README changelog. They
add no analyzer errors; that file's 8 remaining warnings are pre-existing.
⚠ They still need to reach testers in an **app build** — a web deploy of this
repo can't carry them.

#### What LandAndHouseWeb has to do

The third project (`~/FlutterProject/land_and_house_web_new` — a FlutterFlow
export, Firebase project `srisawad-mobile-app-qa-360402`) is **the user's to
change**; the local copy is read-only reference and was not edited. The action
**already exists there**: `lib/custom_code/actions/open_p_loan_extra.dart`,
called from `customer_topup/topup_card_page/topup_card_page_widget.dart:7337`
when `productListItemItem.productCode == 'PLD001'`:

```dart
import 'package:web/web.dart' as web;

Future openPLoanExtra(String dbName, String contractNo) async {
  web.window.location.href = 'srisawad://ploan-extra'
      '?dbName=${Uri.encodeQueryComponent(dbName)}'
      '&contractNo=${Uri.encodeQueryComponent(contractNo)}';
}
```

The host cancels that navigation (the card does **not** move) and opens this
build. Pass only `db_name` + `contract_no` — `hashThaiId` and `token` are added
natively, and **no `amount`**: the resume route reads `topup_extra` itself.
`&amount=` stays supported for the case where the card lets the customer change
the figure.

⚠ **That version only works inside the app.** `srisawad://` resolves to nothing
in a plain browser, so the button appears dead when testing LandAndHouseWeb on
the web. A browser-capable variant was written on 2026-07-30 for the user to
paste into FlutterFlow: it branches on
`globalContext.has('flutter_inappwebview')` — the same host check this build
uses — keeping the custom scheme inside the app and navigating straight to
`<loan-universal>/pLoan/resume?hashThaiId=…&token=…&dbName=…&contractNo=…` in a
browser, where `hashThaiId`/`token` come from `FFAppState()`
(`hashThaiIdAppState` / `accessToken`) since no host is there to add them. Same
signature, so no FlutterFlow argument changes are needed.

#### Testing the deep link in a browser

No WebView needed — the mobile API sends `access-control-allow-origin: *`.

```
https://sawad-loan-universal-uat.web.app/pLoan/resume?hashThaiId=<HASH>&token=<JWT>&dbName=<DB>&contractNo=<NO>
```

`contract_no` shows on step 1's card but `db_name` does not, so take both from
`GET /loan/list?hash_thai_id=<HASH>` (bearer `<JWT>`). With
`--dart-define=P_LOAN_MOCK=true` the two fixtures cover both amount branches:
`MOCKDB` / `MOCK-C-6701002` has `topup_extra` 20000 (used), `MOCKDB` /
`MOCK-M-6701001` has 0 (falls back to 35000). In a plain browser `closeWebview`
is unavailable, so step 3's back and the success button fall back to `/`.

#### Step numbers: Extra is 4, new P-Loan is 6

**The agreed way to refer to these screens** (set 2026-07-30). When a step number
is mentioned, resolve it here and confirm against the **screen title** before
editing — the two numberings collide, and a report about "step 4" was once acted
on against the wrong page because of it.

| Extra (4) | New (6) | Page (`lib/p_loan/application/`) | Title |
| --- | --- | --- | --- |
| **1** | — | the LandAndHouseWeb top-up card — **not in this app** | — |
| — | **1** | `p_loan_contract_select_page` | เลือกสัญญา |
| — | **2** | `p_loan_amount_page` | ข้อมูลยอดจัดสินเชื่อ |
| **2** | **3** | `p_loan_installment_page` | เลือกจำนวนงวด |
| — | **4** | `p_loan_vehicle_photos_page` | รูปภาพหลักประกัน |
| **3** | **5** | `p_loan_customer_data_page` | ตรวจสอบข้อมูลส่วนตัว |
| **4** | **6** | `p_loan_conclusion_page` | สรุปรายละเอียดของสัญญา |

In **code** the numbering is still the six-screen one: pages call
`_flow.stepNumber(6)` and `PLoanEntry` maps it down, so `stepNumber(6) == 4` on
the Extra path. Translate; don't assume a spoken number matches a literal.

⚠ The count comes from the **entry point**, not the product: an Extra started
from *this* app's home menu still runs the 6-step indicator. The 4-step count is
the top-up-card entry, which is how Extra ships.

#### Two products, one flow (`PLoanKind`)

Step 1 offers both, and everything after it is the same six screens:

| | `PLoanKind.extra` — **สินเชื่อเพิ่ม** | `PLoanKind.newLoan` — **ขอสินเชื่อใหม่** |
| --- | --- | --- |
| What | more money against an existing contract | a fresh personal loan |
| Step 1 | the contract carousel | the soft-orange card above it |
| Amount | **fixed** at `topup_extra`, field read-only | **starts blank**, customer types it |
| Bounds | none — `min/max_topup_amount` are the *top-up* product's | none client-side (see below) |
| Payout | request − duty | request − duty |
| Step 2/3 pricing | `/topup/detail` on entry, `/topup/calculator` on blur | **no top-up call**; provisional client estimate on ถัดไป (interim — see below) |
| Step 4 collateral | read off `/topup/detail` | **customer types it** (see below) |
| Step 5 payout account | read off the contract | **customer types it** (see below) |
| Submits to | `POST /topup` | `POST /SavePloanContract` |

`PLoanFlow.kind` is set on step 1 and read by every screen after it. The Extra
path is byte-for-byte what it was; only the new path is new, and only it shows
the `PLoanKindBanner` strip, so an unmarked flow is an Extra.

**A new P-Loan has no contract at all.** `refContractNo` ("เลขที่สัญญาอ้างอิง")
is an **Extra's** field — it names the contract the top-up is raised against —
and a new P-Loan is raised against nothing. `PLoanFlow.contract` is null for
that whole flow. This replaced an earlier "data reference" design where step 1
picked a contract for both products; that was wrong about the product.

Consequences, all load-bearing:

- **Step 1 offers the new-loan card even with zero contracts.** An empty
  `/loan/list` is now a notice under the card ("ไม่พบสัญญาที่สามารถขอสินเชื่อ
  เพิ่มได้") instead of an error view that ended the flow for both products.
  The card names no contract.
- **Every `/topup/*` endpoint is unreachable** (all keyed by `db_name` +
  `contract_no`) — see **New-P-Loan pricing (interim)** below.
- **Collateral and payout account are stated by the customer**, not read off a
  contract — see below.
- **`POST /pdf/loan` is unreachable too**, which is what blocks a new-loan
  submit today — see **Step 6 documents** below.
- `refContractNo` goes out **empty and is not reported** as unresolved
  (`PLoanSubmission._absentByDesign`): a field this product does not have is
  not a field the flow failed to fill. `branchID`/`branchId` *is* reported —
  the application is filed by some branch, we just have no source for which.

**The two kinds submit to different endpoints, and must.** `POST /topup` books
against `contract_no`, so posting a new P-Loan there would file a top-up of the
customer's existing loan for an amount never approved against it.
`PLoanFlow.toSubmissionJson()` **throws** for `newLoan` (pinned by
`test/p_loan_flow_test.dart`) and `PLoanFlow.submitTarget` picks the endpoint;
step 6 switches on it. A new P-Loan goes to the P-Loan save API below.

**P-Loan Extra's amount is not the top-up amount.** Instructed 2026-07-30:
*"p-loan extra use same data from topup card but request amount is fixed with
topup_extra, ignore min max."* So an Extra reads the same `/topup/detail` payload
the top-up card is built from, and then:

- the request amount **is `topup_extra`**, exactly — `default_topup_amount`
  ("วงเงินสินเชื่อใหม่", the top-up total) is never substituted for it;
- it is **fixed**: step 2's field is `readOnly` for an Extra, and the source's
  min/max range guidance is replaced with a "กำหนดไว้แล้ว" note. The old
  prepaid-interest lock message went with it — `interest_paid_flag` is no longer
  *why* the field is read-only, so stating that reason would be wrong;
- **`min/max_topup_amount` are not applied.** They bound the *top-up* product.
  `MLOAN` / `ฮฮM680702003NF61X` is the case that proved it: `topup_extra` 2,000
  against `min_topup_amount` 8,000, so range-checking the offer rejected it and
  quietly filed the top-up total (12,000) instead. Verified with the live
  calculator that `/topup/calculator` prices 2,000 happily (6–36 งวด, ฿357/mo at
  6). `LoanAmountDetail.isAmountAllowed` still exists but nothing in `lib/` gates
  on it;
- **`0` means no offer**, not "fall back to something": step 2 blocks with
  ไม่พบวงเงินเพิ่มเติม and the deep link reports the same.

`PLoanFlow.isRequestedAmountAllowed` therefore range-checks **neither** kind —
an Extra needs `> 0`, a new loan `>= newLoanMinimumAmount`.

**The payout formula was changed to match, later the same day.**
`PLoanFlow.payoutAmount` is `requested − duty` for both kinds; it used to deduct
the reference contract's closing balance as well, which on the contract above
gave `2,000 − 7,740 − 1 = −5,741` and put that in `transfer_amount`. See
**Step 6 documents** for the row it feeds and Outstanding #8 for the history.

**No invented amount limits.** For a new loan the only client-side rule is
`PLoanFlow.newLoanMinimumAmount` (100 — the rounding unit). If the real product
has a floor or ceiling it belongs on the server or in the config, not guessed
here. The interim estimate below prices any amount ≥ that minimum; the real
calculator will impose whatever bounds it has.

**New-P-Loan pricing (interim — no calculator API yet).** A new P-Loan makes
**neither** top-up pricing call:

- **Step 2 (`p_loan_amount_page.dart`) makes no top-up call on entry.**
  `GET /topup/detail` is keyed by `db_name` + `contract_no`, which a new P-Loan
  does not have. It starts from a bare `LoanAmountDetail(code: '200')` and shows
  a blank amount field. The Extra path is unchanged (fetches `/topup/detail`,
  prices on entry and re-prices on blur).
- **Step 3 installments are a client-side estimate.** The new-P-Loan product has
  no installment-calculator endpoint yet, and `/topup/calculator` can't stand in
  (same missing contract). So `PLoanApi.calculateNewLoanInstallments` returns
  `provisionalNewLoanPlan` (`models/new_loan_installment.dart`) — flat-rate
  add-on interest over `[12,24,36,48,60]` months at a placeholder `1.25%/month`,
  standard stamp duty (1 baht per 2,000) — run from the **ถัดไป** button on the
  amount the customer typed. Its rate/duty are folded back into the flow
  (`LoanAmountDetail.copyWith` now also carries
  `interestRate`/`dueDay`/`firstDueDate`). Step 3 shows a provisional-estimate
  note so the figures aren't read as a final quote.

This is deliberately **separate** from `kPLoanUseMockData` (off in production,
deleted with mock mode): the estimate runs in the *live* flow.
`PLoanApi.calculateNewLoanInstallments` is the seam — when the real endpoint
lands, swap its body and delete `new_loan_installment.dart`; no screen changes.
The placeholder rate and tenor list are `const`s at the top of that file.

**A new P-Loan inherits no facts from its reference contract** (`NewLoanDetails`
in `models/p_loan_flow.dart`). Because the flow was forked from the top-up one,
every screen after step 1 used to read the reference contract for things that
describe a *different* loan — step 4 showed `ยี่ห้อสินค้า HONDA` off
`/topup/detail`, and steps 5–6 showed that contract's payout account. The
customer could not correct either, and both reached the submit payload. Now:

- **Step 4 collateral is editable.** A `PLoanCollateralType` picker
  (รถจักรยานยนต์ `M` / รถยนต์ `C` / อื่นๆ `O`) plus ยี่ห้อ / รุ่น / ปีที่ผลิต
  (required) and เลขทะเบียน / จังหวัด / วันหมดอายุทะเบียน (optional). **The
  picked type is what decides which photos step 4 requires** — previously the
  reference contract's loan type did. Changing it drops photos the new type
  does not ask for, and the photo section is withheld until a type is chosen.
- **Step 5 payout account is editable** — bank (from `kPayoutBankCodes`),
  account number, account name. The holder defaults to the customer's own name
  but stays editable. All three are required.
- Only `ปีที่ผลิต` currently reaches a payload (`registerYear`); brand, model,
  plate, province and expiry have **no field in either submit API** and are
  collected because they identify the vehicle being photographed.
- **`ContractSummaryCard` is Extra-only**, and now only on steps **2 and 4** —
  a new P-Loan has no contract to summarise. **Step 6 no longer shows it**
  (removed 2026-07-30 on request): it led the summary screen with a contract
  number the หักยอดเงินต้นสัญญาเก่า row repeats and collateral that is summarised
  further down, i.e. the same facts twice above the fold. (It also briefly
  appeared under a `สัญญาอ้างอิง` header during the "data reference" design;
  on step 4 it sat directly above the fields asking for this loan's collateral.)

  ⚠ Beware which numbering a step number is in — see **Step numbers: Extra is
  4, new P-Loan is 6** below.
- The Extra path is unchanged: `PLoanFlow.loanTypeCode` / `collateral*` /
  `bank*` getters pick the source by kind, so no screen or payload mapper
  branches on it. `canSubmit` additionally requires both blocks for a new loan.

**Step 6 documents — a new-P-Loan submit cannot complete yet.**
`POST /pdf/loan` is keyed by `contract_no` + `db_name` + `from` (the contract's
comcode) + `contract_date`. With no contract there are no three PDFs, so the
read-consent-sign step has nothing to work on:

- `PLoanFlow.canGenerateDocuments` is false for a new loan. Step 6 skips the
  call, keeps the rest of the screen (it is **not** an error — the flow's data
  is fine), and renders `_DocumentsUnavailableNote` in place of the document
  rows. The NDID row goes inert with a `รอเอกสารประกอบสัญญา` placeholder,
  because read-then-sign has nothing to read.
- `canSubmit` requires `documents != null`, so the block is in the model and
  testable, not only in the UI. The bottom message leads with the document
  reason rather than telling the customer to sign something that doesn't exist.
- **This is the seam:** when the new-loan document endpoint exists, make
  `canGenerateDocuments` true for a new loan and point `generateDocuments` at
  it. Note `SavePloanContract`'s 30 fields carry **no** document fields (unlike
  `POST /topup`'s `topup_request_file`/`receipt`/`argeement`), so for a new loan
  the PDFs only ever serve the on-screen step.
- ⚠ Related: `_isExpired` compares the ID card against
  `payment_details.current_date_time` so a wrong device clock can't pass an
  expired card. That clock rides on the contract, so **a new P-Loan falls back
  to device time**. The server re-checks on submit.

**Read the source's history before changing this.** Its `lib/p_loan` folder is a
copy-paste fork of `lib/customer_topup`, only lightly renamed — `ploan_status_page`
differs from `topup_status_page` by 36 lines, all of them class/route names — and
it was left half-finished:

- Its final submit was **unreachable** (`if (!false) { Navigator.pop(); return; }`
  sat directly above `saveNewTopupCall`), so this port is the first version that
  actually posts. **It submits `POST /topup`, not `regmast_ploan.php`** — that
  endpoint family is what the whole flow reads from, so the feature is a top-up
  request wearing P-Loan naming. Rename it if that's wrong.
- Step 2's amount field/slider/validation sat behind
  `if (FFAppState().savePLoanData.isNewPLoan)`, and `savePLoanData` was never
  assigned, so the screen always rendered read-only. **The input is enabled here**
  per the behaviour that dead code documented (bounds from `/topup/detail`, round
  down to the nearest 100, re-run the calculator). That flag turned out to be the
  new-loan product: it is read in exactly one place in the source and assigned
  nowhere, so the new-P-Loan path was designed there and never built. It is
  `PLoanKind` here.
- Its ID check accepted **four hardcoded Thai IDs** alongside the customer's own,
  which let anyone holding one of those cards verify against *any* account. That
  backdoor is **deliberately not reproduced** — `test/p_loan_flow_test.dart` pins
  it shut. Also dropped: a hardcoded dev `hash_thai_id`, a hardcoded contract no.
  in the upload path, a never-cancelled 1 Hz `while(true) setState()` heartbeat
  on three pages, and ~a dozen `if (false)` branches.

Structure:

- `models/` — plain-Dart response models (`loan_contract.dart` for `/loan/list`
  and its nested tree, `loan_amount_detail.dart`, `installment_plan.dart`,
  `loan_documents.dart`, and `new_loan_installment.dart` — the interim
  client-side installment estimate for a new P-Loan, see **New-P-Loan pricing**
  above) plus `p_loan_flow.dart`, the mutable state object
  passed page→page as go_router `extra` (same convention as `LoanRegisterForm`;
  the source kept all of it in a global `FFAppState`). `json_coerce.dart` holds
  the tolerant `asString`/`asInt`/`asDouble` helpers — this API returns `1500`,
  `1500.0` and `"1500"` for the same field.
- **Wire quirks that are real, not typos** — `topup_argeement_file` (agreement),
  `lastest_date` (latest), `car_chassisNo`/`car_engineNo` mixed case, and
  camelCase keys inside `installments[]` while everything around them is
  snake_case. `/pdf/loan` also wants `x-srisawad: x1_c3Jpc2F3YWQ`, not `x1`.
- `components/p_loan_components.dart` — money/date formatters, **`formatPhone`**
  (groups a phone as `###-###-####` for the เบอร์โทรศัพท์ row on step 5 —
  `0863652156` → `086-365-2156`. Only a bare 10-digit run is touched; a 9-digit
  landline, an already-grouped value or one with a country code passes through
  rather than being forced into a shape it hasn't got. **Display only** — the
  payload's `mobileNo` keeps the raw digits), section header,
  amount row, contract + bank cards, loading/error views, bottom button,
  `pickPLoanOption` (the bottom-sheet picker behind the collateral-type and bank
  selectors) + `kPayoutBankCodes`, and `pLoanAppBar` — which carries
  `EnvVersionTag`, so all six flow screens show the build without repeating it.
- `pdf_opener.dart` — conditional import (web/stub) that opens a base64 contract
  PDF via a `Blob` object URL. The consent sheet requires the document to have
  been opened before it will accept consent.
- Step 1 is **slimmed down** from the source's 8,257-line page: the add-on
  product grid (and its Firestore `topupProductConfig` collection), "special
  limit" offers, three dead duplicate card implementations and the taps that
  navigated out into the top-up flow are all left out.
- Deviation worth knowing: for loan types other than `M`/`C` the source's step-4
  confirm button was permanently disabled (a dead end). Here those types require
  the tax-disc photo only, so the flow stays completable.

### P-Loan submission payload (`models/p_loan_submission.dart`)

The wizard carries **everything `regmast_ploan.php` needs** — the same 34 scalar
fields and 12 image groups `submit_form/p_loan_form_page.dart` collects by hand.
Nothing is sent to *that* endpoint from the wizard; what actually ships a new
P-Loan is `PLoanContractSubmission` → `POST /SavePloanContract` (see **P-Loan save
API** below), which reuses these values under its own field names. This mapper
stays as the regmast view of the same data, and as the preview for an Extra:

```dart
final s = PLoanSubmission.fromFlow(flow);
await PLoanApiService().submit(fields: s.fields, imageGroups: s.imageGroups);
```

- **Every field is accounted for** — derived from flow state, a fixed constant,
  or reported in `unresolvedFields`. A field is never filled with a
  plausible-looking guess: a wrong `empId` or GPS district is worse than a blank
  one. `test/p_loan_submission_test.dart` asserts the produced key set equals the
  form's exactly (34, no more, no less), so the two can't drift.
- **Photos carry two wire identities.** `PLoanPhoto.payloadKey` is its field in
  the `POST /topup` JSON; `PLoanPhoto.pLoanGroup` is its regmast image group.
  Several slots share a group — all six vehicle angles are `carImage[]` repeated
  parts — and a slot may have an empty `payloadKey` when only P-Loan has a slot
  for it.
- **`creditAmt` is kind-dependent.** It is the *already-approved* limit, which
  for an Extra is the contract's top-up headroom. A new P-Loan has none until
  underwriting sets one, so it is left blank and reported in `unresolvedFields`
  rather than borrowing the reference contract's — that number describes a
  different product. `requestCredit`/`loanAmt` carry what the customer asked for
  either way.
- **`bankCode` / `bankAccNo` / `bankAccName` / `registerYear` are also
  kind-dependent**, and all four go through `PLoanFlow`'s getters rather than
  reading `contract`/`amountDetail` directly. An Extra takes them off the
  contract it draws on; a new P-Loan takes what the customer entered on steps 4
  and 5 (see **A new P-Loan inherits no facts from its reference contract**).
  Blank ones are reported in `unresolvedFields` as usual — `canSubmit` gates on
  them, so only the `อื่นๆ` collateral type can reach submit without a
  `registerYear`.
- **Host-supplied inputs.** `empId`, `mktChannel` and `customerSource` come from
  optional launch params (`?empId=&mktChannel=&customerSource=`) via `AppState`.
  `gpsProvinceId` / `gpsAumphurId` are **ids, not names**, so they need a lookup
  against lat/lng that this flow does not perform — they stay blank and are
  reported.
- **Groups with no capture step** — `eSignatureImage`, `requestDocImage` and the
  four `coBorrow*` co-borrower groups — are listed in
  `PLoanSubmission.unsupportedImageGroups`. Adding a co-borrower or signature
  step is what would fill them.
- Step 4 gained two **optional** attachments for the P-Loan-only groups
  (เล่มทะเบียนรถ, หน้าสมุดบัญชี); being optional they never block the Next button.
- In mock mode step 6 shows a **ดู Payload (P-Loan)** button that dumps the
  fields, file counts and unresolved list — the same QA affordance the submit
  form has. It is **kind-aware**: for a new P-Loan it previews the
  `SavePloanContract` payload that will actually be sent, for an Extra the
  regmast one.

### P-Loan save API (`services/p_loan_contract_api.dart`)

`POST /SavePloanContract` on `https://dev.swpfin.com:8082` — where a **new
P-Loan** is filed. A separate service from the mobile API: different host and
port (`kPLoanSaveApiBase`), HTTP **Basic** auth instead of a bearer token
(`kPLoanSaveApiAuth`), and a `multipart/form-data` body with repeated `group[]`
file parts. Both defines are overridable per build.

`PLoanContractSubmission.fromFlow(flow)` builds it — a **second** mapper beside
`PLoanSubmission`, because the field set is close to `regmast_ploan.php` but not
the same:

| | `PLoanSubmission` (regmast) | `PLoanContractSubmission` (save API) |
| --- | --- | --- |
| Customer name | one `test` field | `firstName` + `lastName` |
| Account holder | — | `bankAccName` |
| Branch | `branchID` | `branchId` (lower `d`) |
| Not sent | — | `transNo`, `transDate`, `payDay`, `initialDate`, `lastPeriodPromo`, `remark` |
| Count | 34 | 30 |

Shared values are **read back from `PLoanSubmission`** rather than re-derived, so
the two payloads can't disagree about the same number; a test asserts every
shared key matches and that the produced key set is exactly the 30 from the
API's own sample (the untracked `etc/api.txt`).

**⚠ Transport: this needs a native-host handler that does not exist yet.**
Verified against the live endpoint on 2026-07-27:

- no `Authorization` header → **401**;
- **no `Access-Control-Allow-*` header on any response**, and the `OPTIONS`
  preflight is 401'd — so a browser upload is blocked before it is sent;
- `GET`/`OPTIONS` with valid auth → 404. The route is POST-only.

So it can't be called from a plain browser at all, and inside the WebView it
needs the host's new **`httpMultipart`** bridge handler (contract + host snippet
in `native_bridge.dart`). `sendMultipartGroupsApiRequest` tries the bridge, falls
back to a direct upload if the host is older, and when that fails too says which
handler is missing. CORS headers on the endpoint would be the other fix; either
side closes it.

**⚠ The Basic credential ships in the bundle.** It is a shared service account
(`prod` in the username, on the dev host) baked in as a `--dart-define` default,
the same way `kNdidApiKey` is — and a define changes where a value comes from,
not who can read it. Anyone can pull it out of `main.dart.js`. The fixes are
server-side: proxy this endpoint behind the mobile API, or issue a credential
scoped to this client that can be rotated on its own.

**Fields the flow can't fill**, reported in
`PLoanContractSubmission.unresolvedFields` rather than guessed:
`gpsProvinceId`/`gpsAumphurId` (ids needing a lat/lng lookup), `latitude` and
`longitude` (never assigned — the flow has no device-location step; the
customer's registered coordinates on `CustomerDetail` are deliberately **not**
substituted, being a different thing from where the application was raised),
`creditAmt` for a new loan, and `empId`/`mktChannel`/`customerSource` when the
host doesn't pass them. On a refusal the client appends the blank ones to the
server's message, because "HTTP 400" against 30 form fields is unactionable.

### Step 6: contract documents + PDPA consents

(Extra step 4 in the spoken numbering — see **Step numbers** above.)

**`สรุปยอดสินเชื่อใหม่` is new-P-Loan only.** Hidden for an Extra on request
(2026-07-30). Every row in it was a top-up framing — the reference contract's
headroom (`ยอดจัดสินเชื่อเดิม` / `สินเชื่อวงเงินอเนกประสงค์`, the `topup_extra`
row / `รวมยอดวงเงินที่อนุมัติ`) plus `หักยอดเงินต้นสัญญาเก่า`, the principal a
top-up would clear. An Extra draws against none of it. The requested amount is
still on screen as `ยอดจัดสินเชื่อ` under `รายละเอียดคำขอสินเชื่อใหม่`.

It took `จำนวนเงินที่จะได้รับ` with it; **`ยอดโอนเงินเข้าบัญชี`** in the next
section replaces it — see below.

**`รายละเอียดคำขอสินเชื่อใหม่` for an Extra** (instructed 2026-07-30) reads:

| Row | Value |
| --- | --- |
| `ยอดจัดวงเงินอเนกประสงค์` | `requestedAmount` — the **full** offer (`ยอดเต็ม`) |
| `ค่าอากรแสตมป์` | `fee_amount` — **the calculator's**, see below |
| `ค่างวด` / `จำนวนงวด` / `ดอกเบี้ย (ต่อเดือน)` / `ชำระทุกวันที่` | as before |
| `ยอดโอนเงินเข้าบัญชี` | `PLoanFlow.payoutAmount` = amount − that duty |

**Two endpoints return a `fee_amount`, and the calculator's is the one used.**
`GET /topup/detail` gives the duty on the top-up *total* (**6** on
`MLOAN`/`ฮฮM680702003NF61X` — ฿1 per ฿2,000 of 12,000), while
`POST /topup/calculator` recomputes it for the amount actually requested (**1**
for 2,000). Step 2 folds the calculator's in with
`detail.copyWith(feeAmount: plan.feeAmount)` — at its load, its blur re-price and
the resume route — so `LoanAmountDetail.feeAmount` is the calculator's from then
on, and `payoutAmount` deducts it (`2,000 − 1 = 1,999`).

Sourcing it from `/topup/detail` instead was tried on 2026-07-30 and **reverted
the same day**: it made the duty 6 on a 2,000 loan, i.e. the duty for a larger
amount than the customer is borrowing.

`ยอดจัดสินเชื่อ` is renamed to **`ยอดจัดวงเงินอเนกประสงค์`** for an Extra, here and
as the heading on step 3 (จำนวนงวด). A new P-Loan keeps `ยอดจัดสินเชื่อ` /
`ยอดจัดสินเชื่อใหม่`, and gets neither new row — its own
`สรุปยอดสินเชื่อใหม่` section already carries the duty and the payout.

**Document viewer.** The three contract PDFs arrive base64 from `POST /pdf/loan`
(as `data:application/pdf;base64,…`, prefix stripped on our side) and are
rendered **inline**: tapping a document row opens a near-full-height sheet with
`PdfInlineView` (`pdf_view.dart`) → `pdfx`'s `PdfView`.

**It renders through pdf.js, not the embedder's PDF plugin — and that is the
point.** Until 2026-07-30 this was an `<iframe>` pointed at a `Blob` object URL,
i.e. the browser's own renderer. That works in desktop browsers and iOS
WKWebView and shows a **blank white frame in Android System WebView**, which
ships no PDF renderer at all — reported from a real device walking
mobile app → LandAndHouseWeb top-up card → P-Loan Extra. `pdfx` decodes the file
in JavaScript and paints each page to a canvas, so it needs nothing from the
WebView.

- **`web/index.html` loads pdf.js 4.6.82 from jsDelivr** — the script, the
  worker (`GlobalWorkerOptions.workerSrc`) and `cMapUrl`/`cMapPacked`. Version
  and URLs are **copied from the LandAndHouseWeb top-up flow**, which renders its
  own contract PDFs this way inside the same WebView — a configuration already
  proven on these devices rather than a fresh guess. Its equivalent screen is
  `customer_topup/pdf_consent_component/`.
- **`cMapUrl` is load-bearing**, not decoration: the documents are Thai, and
  without the character maps pages come up blank of text even though the file
  opened fine.
- ⚠ **pdf.js comes off a third-party CDN at runtime.** If jsDelivr is unreachable
  the viewer goes blank again — the same symptom, a different cause. Self-hosting
  those three files under `web/` is the follow-up (see **Outstanding**).
- `pdf_view_web.dart` / `pdf_view_stub.dart` are **gone**: `pdfx` renders on
  every target, so the conditional import had nothing left to switch on.

**No download, no open-externally.** Instructed 2026-07-30: the customer may read
the contract in the app and consent to it, but not save it out or hand it to
another app. Both affordances are **commented out, not deleted** (`// ignore:
unused_element` on the methods, which are expected back):

| Where | What |
| --- | --- |
| `_ConsentSheet` header | the เปิดในแท็บใหม่ `IconButton` → `_open()` |
| after NDID success | `_downloadAgreementButton()` → `_openAgreement()` |

`pdf_opener.dart` itself is untouched and still compiles. Note the เปิดในแท็บใหม่
route never worked on Android anyway: it calls `window.open`, and the host
registers no `onCreateWindow`.

Because the document is now on screen, the old "you must open it first" gate is
gone — only the acknowledge checkbox remains.

**NDID signing.** Step 6 also carries a **ลงนามเอกสารและยืนยันตัวตน NDID**
section, mirroring the wizard's step 4: a `RegisterFieldRow` that opens the NDID
flow and, on success, flips to a green check + banner + ดาวน์โหลดเอกสาร. It sets
`PLoanFlow.ndidVerified`, which **gates `canSubmit`**.

**Every environment verifies the applicant's own Thai ID.**
`PLoanFlow.ndidThaiId` is simply `customerThaiIdDigits`.

> **Retired 2026-07-31: the non-prod test-identity substitution.** Between
> 2026-07-30 and 2026-07-31 non-prod builds asked NDID about `1234567890123`
> instead of the customer, via `kNdidTestThaiId` /
> `AppEnvironment.ndidThaiIdOverride`. The reason was the **DAP** uat node, which
> had a registered identity for that one id only, so a real customer found no IdP
> and the hop couldn't be exercised at all. The uat gateway
> (`api_url.ndid_url_base`, now `uat.ndid.srisawadpower.com`) carries **real**
> identities, so the define, the getter and its prod-only gate are all **deleted**
> — not defaulted to empty — and `--dart-define=NDID_TEST_THAI_ID` is now
> ignored. Don't reintroduce it: the whole point of UAT here is verifying real
> people.

What that changes for testing: a customer who has not onboarded with any IdP now
gets an **empty registered grid** — `ndid_bank_select_page` already renders
"ไม่พบผู้ให้บริการที่ท่านเคยลงทะเบียน NDID" and leaves the not-registered grid
unselectable — rather than a usable mock bank. That is the node answering
truthfully; pick a test customer who *is* onboarded.

`isThaiIdVerified` still compares the scanned card to `customer.thaiId` and
**not** to `ndidThaiId`; the two now coincide, but a test pins them as separate
concerns (NDID asserts "this person authenticated", the card check asserts "this
card is theirs"). No payload carries `ndidThaiId`. The wizard's
`LoanRegisterForm.ndidThaiId` was never overridden and still just strips its
formatted `thaiId` to digits — which is the **real** customer's id whenever step 1
was seeded from the profile.

Two deliberate differences from step 4:

- It goes **straight to `ndidBankSelect`**, skipping the wizard's
  `document_review_page`. That screen exists to show the contract documents
  before signing, and step 6 already does — with the real PDFs from `/pdf/loan`
  instead of the wizard's mock list. So the gate here is the document consents:
  tapping the row before all three are accepted says so. Read, then sign.
- **ดาวน์โหลดเอกสาร actually opens the PDF** (`pdf_opener.dart`), where the
  wizard's equivalent is a stub SnackBar — that flow has no documents to open.

Note this is distinct from the ID-card block above it: that is KYC on a photo
(`/vision/thai-id-validate`), this is the customer signing the contract with
their bank identity. Both are required. Nothing about the NDID result reaches the
submit payload — neither `POST /topup` nor `SavePloanContract` has a field for
it, and `eSignatureImage` stays empty because NDID produces a verification
reference, not an image.

**PDPA consents.** Two checkboxes at the bottom of step 6 feed
`marketingConsent` / `sensitiveConsent` on the flow, which map to the payload's
`marketingConsent`/`sensitiveConsent` as `Y`/`N`. They used to be hardcoded `Y`.

- **ยินยอมข้อมูลอ่อนไหว is required** and gates `PLoanFlow.canSubmit` — the
  application can't be assessed without it.
- **ยินยอมการตลาด is a genuine opt-in** and deliberately gates nothing.
- `N` is a real answer, so neither ever appears in `unresolvedFields`.

### Mock mode (demo switch — off by default)

The flow runs against the **live mobile API**. Fixtures remain behind
`kPLoanUseMockData` in `config/app_environment.dart`, which **defaults to
`false`**, for demoing without a backend or reproducing a state the API can't
currently produce:

```sh
flutter build web ... --dart-define=P_LOAN_MOCK=true
```

- Fixtures: `p_loan/application/models/p_loan_mock.dart`. Built by feeding JSON
  through the real `fromJson` constructors, so a wire-key change breaks them too
  rather than letting them drift. Also the shared test data for
  `p_loan_flow_test` / `p_loan_submission_test`.
- Guards: one `if (kPLoanUseMockData)` per method in `services/p_loan_api.dart`,
  including `fetchCustomer` / `fetchAddressBook` — which is why steps 1 and 5
  call `PLoanApi` rather than `UserApi` directly.
- While on, every screen shows `PLoanMockBanner` and a submit returns a `MOCK-`
  prefixed transaction number. `test/p_loan_mock_test.dart` asserts the default
  is **off**, so a deployment can never quietly serve fixtures.

### Live API behaviour worth knowing

Verified against `https://dev.swpfin.com:7076`:

- **Business hours.** `GET /topup/detail` answers `code: "503"` with
  `"50301:ท่านสามารถขอสินเชื่อได้ในเวลา 07:00 ถึง 20:30 เท่านั้น"` outside
  07:00–20:30. Step 2 surfaces that message in its error view with a retry —
  it is the API's rule, not a bug.
- **Unknown customer.** `GET /user/detail` answers `results.code: "404"` /
  `"Not Found"` rather than an HTTP error, so step 1 shows "Not Found" when the
  launch `hashThaiId` is not a real customer.
- **Empty contract list.** `GET /loan/list` answers `200` with `results: []`.
  Step 1 renders that as a notice under the new-loan card — it only rules out
  the **Extra**; a new P-Loan needs no contract and stays available.
- The mobile API sends `access-control-allow-origin: *`, which is what lets the
  multipart ID-card upload bypass the native bridge (see `api_transport.dart`).

### Runtime config from Firestore (`services/app_config_api.dart`)

On startup `main.dart` fires an **un-awaited** `_loadRuntimeConfig()` that reads
the Firestore document **`application/public_config`** (path overridable with
`--dart-define=APP_CONFIG_PATH=collection/doc`) from the project in
`AppEnvironment.current.firebaseProjectId`, and publishes it on
`AppState.appConfig`. Verified working on uat: it resolves
`api_url.api_url_base` = `https://dev.swpfin.com:7076` and (since 2026-07-31)
`api_url.ndid_url_base` = `https://uat.ndid.srisawadpower.com`.

**Two endpoints now come from this document**, both by the same rule — config
value first, compile-time define as the degrade-to:

| `api_url` key | Read by | Falls back to |
| --- | --- | --- |
| `api_url_base` (then `api_url_prod`/`api_url_dev`) | `SrisawadApi.baseUrl()` | `AppEnvironment.mobileApiBase` |
| `ndid_url_base` | `NdidApi.baseUrl()` | `kNdidApiBase` |

`AppConfig.urlFor` trims and strips a trailing slash for both, so a value saved
as `https://host/` can't produce `//idp/list`. Any other key in the map is
reachable through `urlFor` without a code change.

- **No Firebase SDK** — it's a plain `GET` against the Firestore REST API
  through the usual `sendApiRequest` transport, with
  `services/firestore_rest.dart` unwrapping the typed-value format
  (`{"stringValue": …}`, `mapValue`, `arrayValue`, `integerValue`-as-string).
  That decoder is the inverse of `tools/firestore-import/parse-dump.mjs`.
- `AppConfigApi.ensureLoaded()` **memoises** the request, so `SrisawadApi.baseUrl()`
  can await it on every call without re-fetching and without blocking boot.
- It **never throws.** Any failure resolves to an empty `AppConfig`, records
  `AppConfigApi.lastError`, and the API clients fall back to the compile-time
  `AppEnvironment.mobileApiBase`. The reason is `print`ed so a denied read is
  visible in the WebView console.
- **Authenticated with an anonymous identity.** The rules gate the document on
  `request.auth != null`, so `AppConfigApi` first calls
  `FirebaseAuthRest.idToken()` (`accounts:signUp`, memoised, renewed 5 min
  before expiry) and sends it as a bearer. When sign-in fails, the read is
  skipped and the compile-time endpoint is used.
- **Anonymous auth is not an access control** and the code says so: anyone can
  mint a token with the public web API key, which ships in this bundle. What it
  buys is a Firebase UID per reader (traceable, rate-limitable), rules that
  never say `if true`, and the hook App Check would plug into. The **actual**
  protection is that this document holds no secrets.
- **Why `public_config` and not `config`:** rules are per-document, not
  per-field, and `application/config` also holds `agent_web_api_token*`. There
  is no way to expose part of a document, so the non-secret URL map lives in its
  own document. `firestore.rules` allows `get` (not `read`, so the collection
  can't be listed) on that one document and denies everything else, including
  `application/config`.

### API groups (`lib/services/`)

Split into groups on purpose, even though P-Loan and top-up currently hit the
same endpoints — the two products share them because both start from the same
data (an existing contract, its limit, its installment calculation).

| File | Contents |
| --- | --- |
| `srisawad_api.dart` | Shared base-URL resolution, headers, send helper, `SrisawadApiException`, and `GET /loan/list` (shared by both products) |
| `topup_api.dart` | `TopupApi` — `/topup/detail`, `/topup/calculator`, `POST /topup` |
| `p_loan_api.dart` | `PLoanApi` — the single seam the P-Loan flow talks to. Delegates the three shared calls to `TopupApi`; owns `/pdf/loan`, `/vision/thai-id-validate`, and `calculateNewLoanInstallments` (interim client-side estimate for a new P-Loan) |
| `p_loan_contract_api.dart` | `PLoanContractApi` — `POST /SavePloanContract`, the **P-Loan save API** (own host, Basic auth, multipart). Reached via `PLoanApi.saveNewLoan` |
| `user_api.dart` | Customer profile + address book |

**Base URL resolution order** (`SrisawadApi.baseUrl()`):
`api_url['api_url_base']` from the config → `api_url_prod`/`api_url_dev` for the
active env → `AppEnvironment.current.mobileApiBase`. `api_url_base` is preferred
because it is **per-project**: the uat Firebase project's copy holds the uat host
(`https://dev.swpfin.com:7076`) and prod's holds prod, so it can't cross
environments the way the absolute `api_url_prod` key would. Trailing slashes are
stripped, so a value like `https://mobile-api.swpfin.com/` won't produce `//`.

`NdidApi.baseUrl()` follows the same pattern against `ndid_url_base` — see
**NDID API client** — so the NDID gateway is not in the table above but is
config-driven too.

When P-Loan gets its own endpoints, only the delegating methods in `PLoanApi`
change — no screen is touched.

Failures throw `SrisawadApiException`; there is **no mock fallback**, so callers
must render an error state. `POST /topup` replies with a `head`/`body` envelope
unlike every other endpoint here (`head.error_flag == 'N'` means success).

`sendMultipartApiRequest` (in `api_transport.dart`) always uses `package:http`
directly, even inside the host: the `httpRequest` bridge carries its body as a JS
string and can't round-trip binary. That's safe for the mobile API specifically
because it sends `access-control-allow-origin: *` — do **not** reuse it for the
NDID gateway.

### P-Loan submission form (`lib/p_loan/submit_form/`)

A **standalone** data-entry form — *not* part of any wizard — reached from
the third home-menu card (**สมัครสินเชื่อ P-Loan**, go_router route
`/pLoanFormPage`, `AppRoutes.pLoanForm`). Its fields map **1:1** to the legacy
P-Loan submission API `regmast_ploan.php` (originally a PHP `curl` call; the
source `p-loan-api-call.php` is kept **untracked** at the repo root for
reference).

- `p_loan_form_page.dart` — 34 scalar fields grouped into sections (ข้อมูลรายการ
  / ลูกค้า / สินเชื่อ / การโอนเงิน / GPS / ความยินยอม), each an editable
  `RegisterTextField` **seeded with sample values** so the page renders fully
  populated (same mock convention as the wizard). Plus 12 **image-attachment
  groups** (`documentImage`, `cardIdImage`, `carImage`, …) shown as removable
  thumbnails. Each group's **แนบรูป** button opens a source bottom sheet
  (ถ่ายรูป / เลือกรูปจากคลังภาพ): กล้อง uses
  `NativeCameraBridge.captureDocument(<groupKey>)` when the host bridge is
  available (framing mask + native downscale) and otherwise falls back to
  `image_picker`; คลังภาพ always goes through `image_picker`. Unlike the wizard's
  OCR buttons this works in a plain browser too. Note
  `image_picker_for_web` **ignores** `maxWidth`/`imageQuality`, so a
  gallery/browser pick uploads the original-resolution bytes.
  Bottom bar (`SaveNextBar`): **ดู Payload** previews the exact fields + file
  counts in a dialog; **ส่งข้อมูล** submits.
- `services/p_loan_api_service.dart` — `PLoanApiService`: builds the
  `multipart/form-data` POST mirroring the PHP — scalar values as form fields,
  each image group sent as repeated `key[]` file parts
  (`http.MultipartFile.fromBytes`). Base URL defaults to
  `http://10.1.112.74/API/loan/regmast_ploan.php` (overridable); typed
  `PLoanApiException`, 60 s timeout, JSON-or-text decode.
- **Reachability caveat:** the endpoint is internal **HTTP** on a private IP, so
  a live submit only works where the WebView/host can reach `10.1.112.74` (and
  mixed content is allowed). Use **ดู Payload** to verify the field mapping
  anywhere; images only capture inside the native host (`isSupported`).

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
mode 2 / "Authen Only"), `getVerifyStatus()`
(`GET /rp/verify/{referenceId}`, status `CREATED|PENDING|ACCEPTED|REJECTED|
TIMEOUT|CANCELLED`), `closeVerifyRequest()` (best-effort cancel). Errors throw
`NdidApiException` (parses the node's `{status, message}` error body).

**Assurance levels are two shared constants** — `NdidApi.minIal` **2.3** /
`NdidApi.minAal` **2.2**, raised from `1.1` / `1` on 2026-07-30. Both `/idp/list`
and `/rp/verify` read them, so the bank is verified at the same bar it was
offered under; change them in one place. They are a **filter**, not a
preference: an IdP that cannot meet them vanishes from both bank-select grids.
Verified on the uat node — at 1.1/1 the list is `idp1, idp2, idp4, idp-thaid`;
at 2.3/2.2 it is `idp1, idp2, idp4`, so **ThaID (ไทยดี) drops out**. Narrowed
further by `identifier`: with the NDID test id only `idp1` comes back.
**Transport:** the gateway sends no CORS headers (and 401s preflights), so a
browser fetch is blocked — inside the host every request goes through the
host's `httpRequest` JS bridge handler (native HTTP, allowlisted to the NDID
gateway; contract in `native_bridge.dart`'s doc comment, implementation in the
srisawad app's `loan_universal_web_widget.dart`); plain `http` is only the
plain-browser/dev fallback. The
node manages its own NDID token; client auth is an `X-API-Key` header
(`kNdidApiKey`, `--dart-define=NDID_API_KEY`, has a baked-in default — note a
web build can't keep it secret from clients anyway).

**Base URL is config-driven** (since 2026-07-31), the same shape as
`SrisawadApi.baseUrl()`: `NdidApi.baseUrl()` resolves
`api_url['ndid_url_base']` from the Firestore runtime config →
`kNdidApiBase` (`--dart-define=NDID_API_BASE`, default
`https://dev.swpfin.com/dap`). Config first because the key is **per-project**,
so the uat document points at the uat node and prod's at prod without a rebuild;
the define stays as the degrade-to value when the document can't be read. It's
awaited per request, so `_uri` is `Future<Uri>` now. Point the define at
`http://localhost:7088` to hit a locally-run node — an `http:` URL additionally
needs the WebView to allow mixed content when the app is served over `https:`.

⚠ **The gateway URL and the host's allowlist are coupled across two repos, and
only one of them is editable without an app release.** The host proxies NDID
through `httpRequest` and refuses any URL outside its compiled-in
`_kHttpRequestAllowedPrefixes`. So a Firestore edit can point this build at a
gateway the app then rejects with `URL not allowed` — which is exactly the state
uat is in right now, see **Outstanding** #22.

The uat document currently holds **`https://uat.ndid.srisawadpower.com`**, which
is a *different node* from the DAP dev gateway the define defaults to: it returns
**real banks** (ธนาคารเกียรตินาคินภัทร, เจ เวนเจอร์ส, …) with `logo_url`s, not the
DAP node's `idp1/idp2/idp4`. Because it has **real identities**, the
`kNdidTestThaiId` substitution was deleted on 2026-07-31 (see **NDID signing**) —
the flow now asks about the actual customer everywhere. Note the node also sends
`logo_url` + `has_logo`, which `NdidIdp`/`_toBank` ignore: bank tiles are still
drawn from the hardcoded `_knownBankStyles` colour list, and an IdP outside it
falls back to an orange tile with its id upper-cased.

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
- **⚠ The host only branches on one action, and it matches exactly.**
  `_openCameraForAction` does `action.toLowerCase() == 'selfie'` → the
  `idCardPlusSelfie` framing mask (in-app component) or the **front** camera
  (`image_picker`); **every other action** — `idcard`, `collateral`,
  `circleCamera`, the six vehicle angles, anything — falls through to the plain
  `idCard` mask on the rear camera. So an action name is not free-form: the host
  vocabulary is `collateral` / `idcard` / `selfie`, and a near-miss fails
  silently with a wrong-looking camera rather than an error.
  `PLoanPhoto.selfieWithIdCard` said `selfieCamera` until 2026-07-30 and was
  getting the rear idCard mask because of it; `test/p_loan_flow_test.dart` now
  pins the string. Fixing this **web-side** was deliberate — the host fix would
  need an app release.
- Compress the photo natively (≈1280px / JPEG ~80) before base64 so the bridge
  stays fast. The full handler code lives in the doc comment of
  `native_bridge.dart`.
- **`httpMultipart` handler — ⚠ not implemented by the host yet.** Needed by
  the P-Loan save API, which takes file parts and sends no CORS headers.
  `httpRequest` can't carry it (its body is a single string), so this handler
  takes the parts as **base64 inside its JSON envelope** and the host assembles
  the real multipart request natively. Full snippet in `native_bridge.dart`'s
  doc comment. Until it exists, a new-P-Loan submit fails with a message naming
  it.
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
- `env_version_tag.dart` — the `(UAT ver<n>)` chip in every page's AppBar
  `actions`, so a tester can read the env + `WEB_VERSION` off any screen.
  **Hidden on prod builds.** The wizard pages each add it themselves; the P-Loan
  flow gets it from `pLoanAppBar` (see below), and its success page — which has
  no AppBar — places it inline where one would be.

## Assets

`assets/` holds `MotorLoanIcon.svg`, `DocumentIcon.svg` (rendered via
`flutter_svg`). `assets/p_loan/` holds the 14 icons for the P-Loan application
flow, copied from the source project. **They live in a subfolder on purpose:**
the source's `MotorLoanIcon.svg` is a different 6.4 KB file that would otherwise
overwrite our 313-byte one. `pubspec.yaml` lists `assets/` and `assets/p_loan/`
separately — a bare `assets/` entry does **not** recurse into subdirectories.

## Dependencies

`shared_preferences` (persist `CustomerDetail`), `google_fonts` (NotoSansThai),
`hexcolor`, `flutter_svg`, `web` (window/console bindings for the native
bridge), `http` (NDID local-node API client + P-Loan `regmast_ploan.php`
client), `image_picker` (camera/gallery picking for the P-Loan attachment
groups; on web it's a hidden `<input type="file" accept="image/*">`, so it needs
the WebView host to support the file chooser), **`pdfx` 2.9.2** (renders the step-6
contract PDFs; pinned to the version the LandAndHouseWeb top-up flow uses, and
**needs the pdf.js script tags in `web/index.html`** — see **Step 6 documents**.
It also pulls native plugins for Android/iOS/desktop, harmless in a web-only
build, but do not open a document under `flutter test` — pdf.js isn't there).
The wizard's OCR/document capture
still goes through the host bridge — the host owns that camera. SDK
`^3.10.4` — code uses **Dart dot-shorthand syntax** (e.g.
`colorScheme: .fromSeed(...)`, `mainAxisAlignment: .center`); needs a recent
toolchain (built on Flutter 3.38 / Dart 3.10).

## Known quirks / gotchas

- `flutter analyze` reports **39 pre-existing `info` lints**
  (`use_super_parameters`, `withOpacity` deprecation, `unnecessary_underscores`,
  `use_null_aware_elements`) in the original screen code — **no errors or
  warnings**. That count is the baseline: if a change makes it 40, the extra one
  is yours. New code uses the modern forms (`withValues`, `?value` map entries)
  rather than matching the surrounding lint.
- **The repo is not `dart format`-clean** (29 of 41 files predate it). Don't run
  a repo-wide format — it buries real changes in whitespace. Match the local
  style by hand.
- Buddhist-era dates: the UI shows/expects B.E. `dd/MM/yyyy` (year = CE + 543).
  `_formatBuddhistDate` assumes a year > 2200 is already B.E. Today's "2569" =
  2026 CE.
- `CustomerDetail` JSON keys are **snake_case** (API contract); the Dart fields
  are camelCase — keep the `fromJson`/`toJson` mapping in sync when adding
  fields.
- Non-web targets: `NativeCameraBridge` is a stub that throws; the OCR button
  shows a "ใช้ได้เฉพาะในแอป" snackbar (guarded by `NativeCameraBridge.isSupported`).

## Security posture

`firestore.rules` (deployed to **both** projects) is an allowlist of exactly one
document:

```
match /{document=**}            { allow read, write: if false; }   // baseline
match /application/public_config { allow get: if request.auth != null;
                                   allow list, write: if false; }
```

**History worth not repeating:** uat was briefly left at
`allow read, write: if true`. That was verified exploitable with zero
credentials — both `agent_web_api_token` values were readable and arbitrary
writes succeeded (a probe document was written, then deleted). The rules file
exists to stop that recurring; it is checked in, so deploy it with
`firebase deploy --only firestore:rules -P uat|prod` after any change.

Credentials that ship in the web bundle, and therefore are **not** secret from
anyone who opens the app: the Firebase web API key (fine — it grants nothing),
`kNdidApiKey`, and `kPLoanSaveApiAuth` (**not** fine — a shared service account;
see **P-Loan save API**).

~~**One identity check is deliberately weakened off prod.**~~ **Closed
2026-07-31.** `kNdidTestThaiId` made non-prod builds run NDID against
`1234567890123` rather than the applicant, because the DAP uat node had no other
registered identity. The uat gateway now has real ones, so the define and its
`ndidThaiIdOverride` gate are **deleted** and no environment substitutes an
identity — `PLoanFlow.ndidThaiId` is the customer's own id, pinned by a test. No
build flag can bring the substitution back.

**No identity check is weakened anywhere now.** Keep it that way: if a future
environment lacks test identities, the answer is to register them on that node,
not to point the client at somebody else's id.

## Outstanding (next session starts here)

Grouped by who has to act. Nothing here is a bug in shipped behaviour — each is
either a decision someone else owns, or something left undone on purpose with the
reason recorded.

**Needs someone else to act:**

1. **Rotate `agent_web_api_token` and `agent_web_api_token_uat`.** They were
   readable by anyone while the uat rules were open. Closing the rules does not
   un-leak them.
2. **Implement the `httpMultipart` bridge handler in the host app**
   (`loan_universal_web_widget.dart`; full snippet in `native_bridge.dart`).
   Until then **a new-P-Loan submit cannot succeed** — the save endpoint sends no
   CORS headers, so the browser blocks the upload. The app already fails with a
   message naming the handler. CORS headers on the endpoint would fix it from the
   other side instead.
3. **Do something about `kPLoanSaveApiAuth`.** Proxy `SavePloanContract` behind
   the mobile API, or issue a client-scoped credential. A `--dart-define` moved
   where the value comes from, not who can read it.
4. **Bump `sawad_loan_universal_version_uat` in the *srisawad host's* appConfig**
   to match the deployed `WEB_VERSION` (**50** as of 2026-07-31), or the host's
   stale-cache auto-reload never fires.
5. **`empId` / `mktChannel` / `customerSource`** reach the payload only if the
   host appends them as launch params. They are blank otherwise and reported.
6. **A new-P-Loan document endpoint is needed.** `POST /pdf/loan` is keyed by a
   contract and a new P-Loan has none, so its three PDFs — and therefore the
   consent rows, the NDID signing and the submit gate — are unreachable. This
   blocks a new-loan submit **before** #2 does. Seam:
   `PLoanFlow.canGenerateDocuments` + `PLoanApi.generateDocuments`; step 6
   already explains itself in place. If a new P-Loan is meant to sign nothing
   pre-approval, the fix is instead to drop that section for the new kind.
7. **`branchID` / `branchId` has no source for a new P-Loan.** It comes from the
   contract's `branch_code` for an Extra. Left blank and reported rather than
   guessed; a `?branchId=` launch param or a branch picker would fill it.
8. ~~An Extra's payout deducts the old principal and goes negative.~~
   **Resolved 2026-07-30.** `PLoanFlow.payoutAmount` is now `requested − duty`
   for **both** kinds, per *"ยอดโอนเงินเข้าบัญชี คือ ยอดจัดวงเงินอเนกประสงค์ ลบ
   ค่าอากรแสตมป์"* on the full amount. It had been the *top-up* formula
   (`− closing_balance` as well), which drove `2,000 − 7,740 − 1 = −5,741` into
   the screen **and** into `transfer_amount` / `transferAmt`. The
   `หักยอดเงินต้นสัญญาเก่า` rows on steps 2 and 6 went with it, and
   `LoanAmountDetail.payoutFor` was **deleted** rather than deprecated so the old
   formula can't be picked up by name.
9. ~~LandAndHouseWeb's button is not built yet.~~ **Built** — `openPLoanExtra`
   exists and is wired to `productCode == 'PLD001'` (see **What LandAndHouseWeb
   has to do**). What remains is the user pasting the **browser-capable variant**
   into FlutterFlow if they want the button to work when testing on the web.
10. **The host-app edits need an app release.** `routegenerator.dart` and
    `video_record_web_widget.dart` are committed on `main` in the srisawad repo;
    `loan_card.dart`'s PLD001 chip was added 2026-07-30. Only a new
    Android/iOS build puts the `srisawad://ploan-extra` interception on a
    tester's phone — deploying this web repo can't.

**Open in this repo, deliberately not done:**

11. **🐞 `POST /topup` hardcodes both PDPA consents to `'Y'`.** Found
    2026-07-30, **not fixed** — it is a behaviour change to a submitted field and
    was raised rather than slipped in. `toSubmissionJson()`
    (`p_loan_flow.dart:791-792`) sends `'marketing_consent': 'Y'` and
    `'sensitive_consent': 'Y'` literally, while step 6's checkboxes write
    `flow.marketingConsent` / `flow.sensitiveConsent` — which only
    `PLoanSubmission` and `PLoanContractSubmission` read, and **neither is on the
    Extra path**. So an Extra files `Y` for **ยินยอมการตลาด** even when the
    customer declined it. `sensitive_consent` is harmless in practice
    (`canSubmit` requires it, so it is always true), but marketing is a genuine
    opt-in, which makes this a PDPA-relevant defect, not a cosmetic one. Fix is
    two lines: `_yesNo(marketingConsent)` / `_yesNo(sensitiveConsent)`, the same
    mapping the other two payloads already use.
12. **No live `SavePloanContract` submit has ever run.** Auth, routing and the
    CORS behaviour were verified by probing; the field mapping is verified
    against the API's sample and by tests. One real submit is still needed — it
    was skipped rather than file a junk application in dev.
13. **The top-up-card chain has been walked, but never submitted.** On
    2026-07-30 the user ran the real chain — srisawad app → LandAndHouseWeb
    top-up card → this build — as far as **step 4**, where the PDF viewer turned
    out to be blank on Android (fixed, #18). So the deep link, the host
    interception and steps 3 → 5 → 6's data are all confirmed against a live
    contract (`MLOAN` / `ฮฮM680702003NF61X`). What has still never happened is a
    **live `POST /topup`** from it — nobody has pressed ยืนยัน on a real
    application. Do that before calling the flow done, and note #11 sends the
    wrong marketing-consent value when you do.
14. **`latitude` / `longitude` have no source.** `PLoanFlow` never assigns them —
    there is no device-location step. `CustomerDetail` carries registered
    coordinates, deliberately **not** substituted: "where the application was
    raised" is a different fact. `gpsProvinceId`/`gpsAumphurId` likewise need an
    id lookup from lat/lng.
15. **A top-up-card Extra submits no collateral photos.** Step 4 is skipped by
    design, so `carImage`/`documentImage` are empty and
    `property_image`/`act_image` go out as `''`. A test pins that this cannot
    deadlock `canSubmit`. If `POST /topup` rejects a top-up without vehicle
    shots, this is why.
16. **`firebase.json` cache headers miss `/` and deep links.** Hosting matches
    the requested path, not the rewritten one, so `/index.html` gets `no-cache`
    but `/`, `/pLoan/contract` and `/pLoan/resume` get `max-age=3600`.
17. **prod has no registered web app**, so `AppEnvironment.prod.firebaseApiKey`
    is empty — anonymous sign-in is skipped there and the compile-time endpoint
    is used. Register one and paste the key to enable the config read on prod.
18. ~~Android WebView cannot render the inline PDF.~~ **Fixed 2026-07-30** by
    moving to `pdfx` + pdf.js (see **Step 6 documents**). The `openPdf` bridge
    handler this entry used to call for is **no longer wanted** — it would cost a
    host change and an app release to reach a worse UX than a web-only fix that
    is already proven in the top-up flow. What remains is smaller:
    **self-host pdf.js** (`web/index.html` currently pulls 4.6.82 from jsDelivr,
    so a CDN outage blanks the contract viewer again).
19. **App Check** is not enabled, and the `?token=` JWT still travels in the
    launch URL — now on `/pLoan/resume` too.
20. **New-P-Loan installment calculator API.** Step 2/3 pricing for a new P-Loan
    is a client-side estimate (`PLoanApi.calculateNewLoanInstallments` →
    `new_loan_installment.dart`): the product has no calculator endpoint and
    `/topup/calculator` can't stand in (it is keyed by a contract this product
    does not have). Wire the real call into that seam when it exists and delete
    the interim file; the placeholder rate (`1.25%/month`) and tenors
    (`[12,24,36,48,60]`) live at the top of it.
21. **A new P-Loan's ID-card expiry check uses the device clock**, since the
    server clock it should use rides on the contract. See `_isExpired`.
22. **🚧 An app release is what now stands between uat and a real NDID test.**
    The uat config points NDID at `https://uat.ndid.srisawadpower.com`, which the
    host must allowlist because the gateway sends **no** `access-control-allow-*`
    headers (verified — so the `httpRequest` bridge is mandatory and a plain
    browser cannot substitute for it). `_kHttpRequestAllowedPrefixes` in the
    srisawad host's `loan_universal_web_widget.dart` **has been updated**
    (2026-07-31) — but it is an **uncommitted working-tree edit on `main`** in
    that repo, and like #10 it only reaches a tester in a **new Android/iOS
    build**. Commit/branch it there before it gets lost. Until that build exists,
    every in-app NDID call returns
    `{'status': 0, 'error': 'URL not allowed: …'}`. Two ways to unblock without a
    release: point `ndid_url_base` back at `https://dev.swpfin.com/dap`, or delete
    the key (the build then falls back to `kNdidApiBase`, the same host) — but
    note the DAP node no longer has an identity this build will ask about, since
    the test-identity substitution is gone.

## Conventions

- Thai UI strings inline; English code/comments.
- All styling goes through `LoanRegisterStyles` + `google_fonts` NotoSansThai.
- Build/verify with `flutter analyze --no-pub`, `flutter test`, and
  `flutter build web --release --pwa-strategy=none`. New model fields → update
  both `fromJson` and `toJson` (and `copyWith`).
