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
| Submits | nowhere — final ถัดไป is a SnackBar | `POST /ploan` (**both** kinds) |
| Reads | a customer profile + address book | `/user/detail`, `/loan/list`, `/topup/*`, `/pdf/loan`, `/vision/thai-id-validate` |

There is still **no Firebase SDK** in the app — but Firebase is no longer only
Hosting: the uat project also serves a runtime-config document over the
**Firestore REST API**, read with an **anonymous Auth** token minted over REST
(`services/firebase_auth_rest.dart`, `services/app_config_api.dart`). Two
projects, `prod` and `uat` (see Deploy below).

**Resolved history lives in [`docs/HISTORY.md`](docs/HISTORY.md)**, not here —
replaced designs, closed Outstanding items, the full pentest list, and the
evidence behind decisions that are now just one line below. It is **not**
`@`-imported, so it costs nothing per session: read it when a change touches one
of those areas, and put new history there rather than growing this file. This
file stays under the 150k-character limit Claude Code loads per session; if it
passes that again, archive the next round the same way.

## Current state (read this first)

- **The top-up flow is live too, and it is a different product** (added
  2026-09-11, `lib/topup/`). Home menu → **สินเชื่อเพิ่ม**, or `/topup`. It is
  **not** a P-Loan Extra: a top-up closes the existing contract out and
  reissues it larger, so the old principal comes off the payout and
  `min/max_topup_amount` apply. The two flows share models, services and
  components but have **separate page sets**, so adding it touched no P-Loan
  screen. Read **Top-up flow** before changing either.
- **The P-Loan application flow is the live one.** Its screens have no mock
  fallback (fixtures exist behind a default-off define — see **Mock mode**).
  **Both kinds now file with `POST /ploan`** on the mobile API base (changed
  2026-07-31 to unify the endpoint; **retargeted 2026-08-04** from the old
  `<:8082>/SavePloanContract` to a **bearer-authenticated** call on
  `<api_url_base>/ploan`; body changed to `multipart/form-data` with five file
  parts on **2026-08-07**). This **removed the old submit blocker**: the endpoint
  no longer needs the never-built `httpMultipart` bridge or a baked-in Basic
  credential, so an **Extra can complete** — and one has: a **live submit
  succeeded 2026-08-17** against a real contract (`SLOAN`), which settled the
  multipart, CORS-preflight and body-size questions in one shot. See **P-Loan
  save API** and Outstanding #12.
  A **new P-Loan** is still blocked because it has **no contract** (see
  *A new P-Loan has no contract at all*): `POST /pdf/loan` can't produce the
  documents its submit gate needs. It also **prices steps 2–3 with an interim
  client-side estimate** — no calculator API yet, and the top-up one can't stand
  in (see **New-P-Loan pricing (interim)**).
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
- **The NDID hop is three screens, not two, and it starts with the agreement**
  (2026-08-28): `ndid_terms` → `ndid_bank_select` → `ndid_verify`. Both callers
  push `AppRoutes.ndidTerms` and still await one bool. Its customer-facing text —
  the agreement, the IdP guidance, the waiting message and every failure — is
  **the NDID standard's, quoted, not ours**; see **NDID Common Message
  standard** before rewording anything on those screens. The **Transaction Ref**
  on the waiting screen is the gateway's `transaction_ref` as of **2026-08-31** —
  this app generates none, and reintroducing a local one would put a second,
  different reference in front of the customer. Not yet seen on a live request
  (Outstanding #26).
- **Mock data drives the UI.** `LoanRegisterForm.mock()` (matches "slide 7" of
  the design) seeds every field so screens render fully populated. Option lists
  (brands, models, provinces, installment counts, transfer types) are hardcoded
  `const` lists in the pages, not fetched.
- **Startup params:** the native host launches the web URL with
  `?hashThaiId=<...>&token=<firebase-jwt>` (both appended by the host's
  สมัครสินเชื่อ button / RouteGenerator). `main.dart` reads them into
  `appState.hashThaiId` / `appState.authToken`, then fires an **un-awaited**
  `_loadCustomerProfile()`: `UserApi.fetchUserDetail(hash, token: …)` →
  `appState.customerDetail` (persists + notifies) and
  `UserApi.fetchAddressBook(hash, token: …)` → `appState.customerAddressBook`
  (in-memory). **Both send the bearer token** (see **API groups**).
  - ⚠ **The launch `?token=` is only the FALLBACK now (2026-09-07).** Firebase ID
    tokens expire after an hour and a P-Loan application routinely runs longer, so
    the bearer is resolved **per request** from the host's `getAuthToken` handler
    via `AuthToken.resolve` (`lib/services/auth_token.dart`), wired in at
    `SrisawadApi.authHeaders` — the single credential seam, reached from four
    places (`SrisawadApi.send`, `UserApi._headers`, the `/vision/thai-id-validate`
    upload, and the `/ploan` submit). `appState.authToken` is what a plain browser
    and an outdated host fall back to.
  - ⚠ **Neither launch param survives a reload.** Path URL strategy is on, so
    go_router replaces the whole location on the first navigation and the query is
    gone from `window.location`; they live on only in `AppState`, in memory. Any
    reload the host triggers (stale-build reload, iOS content-process reload, its
    retry button) re-boots this app with both empty. The token recovers itself
    through `getAuthToken`; **`hashThaiId` does not**, so a reload mid-flow still
    lands on `ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง`. Fixing that means
    stashing the non-secret launch params in `sessionStorage` — never the token —
    and is not done. (`PLoanFlow` is in-memory only, so a reload discards all six
    steps regardless.)
  - No caching and no 401-retry in the resolver, deliberately: the host's
    `getIdToken()` is itself a cached read that refreshes near expiry, and the app
    force-refreshes every 60 s while its home page is mounted, so a bridge hop
    always returns a token minted seconds ago. It does carry a 10 s timeout and
    in-flight de-duplication — nothing else bounds the round trip, and two screens
    fire their customer + contract reads in parallel on purpose. While the
  fetch is in flight `AppState.profileLoading` is true
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
flutter test               # 330 tests (models, payloads, headers, NDID terms +
                           # common messages + transaction_ref + the per-gateway
                           # API-key pairing + verify-with-data, the /ploan
                           # failure report, mock-mode guard, the top-up flow's
                           # pricing/outcome rules + its two payloads) — green
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

**The `Stop` hook is configured again** — verified 2026-08-28, when it deployed
this session's work. `.claude/settings.local.json` holds a `hooks.Stop` entry
running `bash tools/deploy-uat.sh` (async, 600 s), so **finishing a turn deploys
uat** whenever `lib/`, `web/`, `assets/` or the pubspec files changed. (The note
here previously said the opposite; that was true on 2026-07-31 and is not now.)

So **two** things ship uat, and they number builds differently:

| | Fires on | `WEB_VERSION` |
| --- | --- | --- |
| The `Stop` hook | finishing a turn with a source change | live version + 1 |
| CI (`.github/workflows/deploy-uat.yml`) | a push to `uat` | GitHub Actions run number |

⚠ Because both are live, a turn that edits code **and** pushes runs both, and
whichever finishes last wins. That is also why `.deploy-version-uat` can sit one
ahead of what the site reports — it records the version the hook *built*, and a
CI release landing after it replaces that build. It is self-correcting (the next
run re-derives from the live site), so a one-off mismatch is not worth chasing.

⚠ **Do not verify a deploy by grepping the bundle for a Thai string** — dart2js
escapes non-ASCII literals, so `grep 'เงื่อนไข' main.dart.js` returns 0 on a
build that plainly contains it. Cost half an hour on 2026-08-28. Grep an ASCII
marker instead (a route path, a `Diagnostics.log` message) or just open the page.

Note the hook was deliberately **not** a
`PostToolUse`/`Write|Edit` hook: that fires after every single edit and would
push dozens of half-finished refactors per task.

Two consequences of CI owning the deploy: **rapid consecutive pushes cancel
each other** (only the branch tip ships — "cancelled" in the run list is not a
failure to chase), and the version stamp jumps to the run number, so
`WEB_VERSION` is not contiguous with what `.deploy-version-uat` last recorded.
[History](docs/HISTORY.md#ci-deploy-consequences).

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
  `/documentAttachPage`, `/documentReviewPage`, `/ndidTermsPage`,
  `/ndidBankSelectPage`,
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
  pushes step 5. Gated by `form.ndidVerified`. The NDID flow it opens now begins
  at `ndid_terms_page`, not the IdP picker.
- `document_review_page.dart` — **ตรวจสอบเอกสาร** (slide 8 frame 2). Contract-doc
  list + an acknowledge checkbox; the "ลงนามเอกสารและยืนยันตัวตน NDID" button
  starts the NDID flow — at `ndid_terms_page` since 2026-08-28 — and, on success,
  pops `true` back to step 4.
- `ndid_terms_page.dart` — **เงื่อนไขและข้อตกลงที่เกี่ยวข้อง NDID**, the NDID
  service agreement (added 2026-08-28). **This is now the first screen of the
  NDID sub-flow**, ahead of the IdP picker: both `document_review_page` (wizard
  step 4) and `p_loan_conclusion_page` (P-Loan step 6) push
  `AppRoutes.ndidTerms`, and it forwards to `ndidBankSelect` on ยอมรับ,
  propagating that chain's `true` back unchanged — so neither caller changed
  shape, they still await one bool. ปฏิเสธ pops `false` and ends the hop.
  Takes an `NdidSubject` purely to hand onward, like the two screens after it.

  **The agreement is one continuous scroll**, not a pager — a `PageView` was
  built first and replaced the same day; it also cannot be mouse-dragged on
  Flutter web. See [docs/HISTORY.md](docs/HISTORY.md#ndid-terms-pageview).

  Wording lives in `ndid_terms_content.dart`, **generated** from the supplied
  Apple Pages file rather than retyped: `.pages` is a zip whose
  `Index/Document.iwa` is Snappy-framed protobuf, so the text was decompressed
  and lifted out verbatim. Clause numbers are structural
  (`NdidTermsClause.number` / `NdidTermsItem.marker`), because the source had
  literal `3.<tab>` prefixes on clauses 3, 4 and 6–9 while 1, 2 and 5 were
  auto-numbered by Pages and carried no digits at all. `test/
  ndid_terms_content_test.dart` pins clauses 1–9, clause 3's five sub-items,
  and that no clause re-renders its own number.

  Acceptance is **not** stored on the flow — every run of the NDID hop shows
  the agreement again, which is what a per-verification consent means.
  ⚠ ปฏิเสธ is recorded with `Diagnostics.log` only (the design's
  "กรณีปฏิเสธมีเก็บ log" note). That trail is **session-local**, readable from
  the `(UAT ver…)` tag; there is no consent-log endpoint to post it to — see
  Outstanding #23.
- `ndid_bank_select_page.dart` — **เลือกผู้ให้บริการ NDID** (slide 8 frames 3–4).
  **Shared with the P-Loan flow's step 6**, and reached from `ndid_terms_page`
  rather than from either caller directly. It and `ndid_verify_page` take a
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
  **Both grids are selectable** (changed 2026-08-04). The not-registered grid
  used to render at 0.45 opacity with `onTap: null`; it now passes
  `enabled: true` like the registered one. `_next` never branched on which grid
  a bank came from — it only reads `bank.idpId` — so an unregistered IdP goes
  through the identical `POST /rp/verify`; the NDID gateway/bank app then walks
  the customer through sign-up before verifying. The two headers stay as a hint
  about what happens next, and a note under the second grid says an unregistered
  pick must register in the bank's app first.

  **Tiles show the gateway's own logo** (`logo_url` / `has_logo` on `NdidIdp`,
  added 2026-07-31) via `Image.network(..., webHtmlElementStrategy:
  WebHtmlElementStrategy.prefer)`. That argument is **load-bearing, not a
  preference**: the gateway serves logos with no `access-control-allow-*` header
  *and* its placeholder is an **SVG**, so Flutter web's default byte-fetch path
  fails twice over — CORS blocks it and `dart:ui` has no SVG decoder. `prefer`
  puts the image in an HTML `<img>` element, which needs neither. The
  `httpRequest` bridge cannot substitute: it returns its body as a UTF-8 string,
  which can't carry a JPEG.

  `has_logo: false` means the shared `_default.svg` (a neutral grey bank glyph) —
  still displayed, being better than a bare code.

  ⚠ **Logos are rationed to four tiles, registered grid only** (`_kMaxLogoTiles`,
  2026-08-17). Each one is a **platform view**, and sixteen of them killed the
  WKWebView content process on iOS — the white-screen bug. Every other tile falls
  back to `_codeMark`. See **On-device diagnostics** → *What it found* for the
  proof; **do not render them unconditionally again.**

  **The fallback mark is initials, not the node id.** `_toBank` used
  `idp.id.toUpperCase()`, which read fine on the DAP node (`idp1`) and broke on
  the uat gateway, whose ids are **UUIDs**: 36 characters in a 44×44 box, clipped
  across three lines — seen on a real device, and on the *only tappable tile* the
  test customer had. `_initials()` now takes up to three word-initials from the
  English name (`Mock Auto 1` → `MA1`), else a 3-grapheme prefix of the Thai name
  minus the `ธนาคาร` prefix, and the text is `maxLines: 1` + ellipsis so no future
  value can overflow again. `_knownBankStyles` still supplies the colour/short
  code for the seven big banks.
- `ndid_verify_page.dart` — **ยืนยันตัวตน** countdown screen → **ยืนยันตัวตน
  สำเร็จ** (slide 8 frame 5 + final frame). One page, two phases. The bank's own
  app (K+ PIN pad, NDID consent) is **third-party — not rebuilt**. Inside the
  host it creates the real request (`NdidApi.createVerifyRequest`, 1 h
  `request_timeout` matching the countdown) and polls every 3 s.

  **Polling only runs while this page is visible**, and verifying means leaving
  it — the bank's app for a customer, the **NDID UAT console** for a tester. A
  backgrounded WebView throttles or suspends its JS timers, so the poll is not
  running while you are away. Four things in `ndid_verify_page.dart` handle
  that, all load-bearing
  ([why](docs/HISTORY.md#ndid-verify-polling)):

  - an `AppLifecycleListener(onResume:)` **polls immediately** on return;
  - a **ตรวจสอบสถานะ** button, so a tester never depends on the timer;
  - **poll failures are not silent** — individually ignored (one flaky response
    must not kill a live request), but after 3 consecutive ones a warning names
    the error. Silence made an unreachable gateway look exactly like a customer
    who hadn't approved yet;
  - the countdown hitting 00:00 **cancels the poll** and shows the timeout —
    the two timers are otherwise independent.

  A `_polling` guard also stops overlapping requests piling up, since
  `Timer.periodic` fires regardless of whether the previous poll finished and one
  can take up to the 30 s API timeout. `ACCEPTED` →
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
| Submits to | `regmast_ploan.php` (internal IP) | `POST /SavePloanContract` (both kinds) |
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

⚠ **This build's own top-up card seeds the route instead of making it
re-fetch** (added 2026-09-11). The topup contract card has already loaded
`/loan/list` and `/user/detail` to draw the carousel the customer just tapped,
so it passes both as `extra` (`PLoanResumeSeed`) and the resume screen skips
those two calls — two round trips the customer was otherwise waiting through
for data already in memory.

The seed is **an optimisation on one path, never a requirement**. The
LandAndHouseWeb card reaches this route through the host in a *fresh WebView*
and has nothing to hand over, and a reload drops `extra` — both still fetch. So
the property the query-string design was chosen for holds: a refresh reproduces
the state rather than resuming a stale copy.

⚠ **The query string stays the authority.** A seed is used only when
`PLoanResumeSeed.matches` confirms it is for the route's own `dbName` **and**
`contractNo` — both halves, since contract numbers are unique only within a db.
Otherwise it is ignored and the contract is fetched, because the URL is what a
reload would use and the two must never resolve differently.

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
| Submits to | `POST /ploan` | `POST /ploan` |

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

**Both kinds submit to `POST /SavePloanContract`** — changed 2026-07-31 on
instruction (*"in p-loan extra step 4 we will save to
https://dev.swpfin.com:8082/SavePloanContract"*; step 4 there is the Extra
numbering, i.e. `p_loan_conclusion_page`).

This settles the question this port was left holding. An Extra went to
`POST /topup` because the FlutterFlow source it was forked from was a **top-up
request wearing P-Loan naming** — the note here used to read *"Rename it if
that's wrong"*. It was wrong: a P-Loan Extra is a **P-Loan contract that
references an existing one**, not a top-up of it. It draws a separate
`topup_extra` line rather than closing the old loan out — which is also why
`payoutAmount` stopped deducting the old principal on 2026-07-30. Now
`refContractNo` is the only field that separates the two kinds.

`PLoanFlow.submitTarget` returns `pLoanSaveApi` unconditionally, and
`PLoanApi.saveNewLoan` was renamed **`savePLoanContract`**. Step 6's `switch`
keeps its unreachable `topup` arm so it stays exhaustive and reverting is one
line. `toSubmissionJson()` (the `/topup` body) is off every submit path but kept
with its tests as the record of that wire format — including its guard, which
still **throws** for `newLoan` so that body can never be built for a product it
would misfile.

~~⚠ **Two host prerequisites, both needing an app release**~~ — **resolved
2026-08-04** by the retarget, and still resolved after the 2026-08-07 move back
to `multipart/form-data`. Both prerequisites were properties of the old
`<:8082>` host (no CORS headers, plus an allowlist entry), not of multipart
itself: `/ploan` is on the mobile API base, which sends
`access-control-allow-origin: *`, so the upload goes direct through
`package:http` and needs no bridge handler. See **Transport** below and
Outstanding #2.

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
copy-paste fork of `lib/customer_topup` that was left half-finished — an
unreachable final submit, an always-read-only amount field behind a flag that
was never assigned (which turned out to be `PLoanKind`), and an ID check with
**four hardcoded Thai IDs** that is **deliberately not reproduced**
(`test/p_loan_flow_test.dart` pins it shut). Full account in
[docs/HISTORY.md](docs/HISTORY.md#flutterflow-fork).

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
  snake_case. `/pdf/loan`'s `x-srisawad` is **per-environment** — `x1` on uat like
  every other call, `x1_c3Jpc2F3YWQ` on prod
  (`AppEnvironment.pdfLoanSrisawadHeader`, split 2026-08-07; it was the special
  value everywhere before that).
- **Step 5 (Extra 3) leads with `ข้อมูลส่วนตัว` → `ชื่อ-สกุล`** (added
  2026-07-31), above the `ข้อมูลโทรศัพท์` section. Its own header rather than a
  second row under the phone one, since a name is not phone data. The value is
  `CustomerDetail.fullName` — first + last, **no `คำนำหน้า`**, matching the label
  — and it is the same getter the new-loan payout-holder default and
  `PLoanFlow.bankAccountName` read, so one customer cannot render two ways on
  the same flow. Read-only for both kinds, like the phone and addresses.
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
stays as the regmast view of the same data:

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
- ⚠ **Step 6 no longer previews the payload.** A non-prod **ดู/คัดลอก Payload
  (POST /ploan)** button used to dump the resolved URL, the form fields, the
  file parts and `unresolvedFields` into a copyable dialog; it was **removed
  2026-09-07** on request. `submit_form/`'s own **ดู Payload** button is a
  different feature and is untouched. What remains for inspecting a real submit
  is the **failure report** on a failed one (see **P-Loan save API**) — which
  only appears when the submit fails, so a *successful* body can no longer be
  read off a device. If that is wanted back, the mapper is unchanged: build
  `PLoanContractSubmission.fromFlow(flow)` and print `fields` / `files` /
  `unresolvedFields`.

### P-Loan save API (`services/p_loan_contract_api.dart`)

`POST /ploan` — where a completed P-Loan application, **both kinds** (an Extra
since the 2026-07-31 retarget), is filed.

**Retargeted 2026-08-04 to a mobile-API-style call**, from the earlier
`<:8082>/SavePloanContract`. It is now just another call on the mobile API:

- **Base URL** = `api_url['api_url_base']` from the Firestore config document
  (`application/public_config`) via `SrisawadApi.baseUrl()` — so on uat it lands
  on `https://srisawad-qa.ecorpgroup.com`, the same host every other mobile-API
  call uses. There is no separate host/port define any more.
- **Auth** = the customer's own Firebase **bearer token** (the `?token=` launch
  param, `PLoanFlow.authToken`). **No service credential ships in the bundle.**
- **Header** `x-srisawad: x1` from `SrisawadApi.headers` like every other
  mobile-API call — `AppEnvironment.current.srisawadHeader` is `x1` on both prod
  and the new uat gateway (uat was empty until 2026-08-04; see below).
- **Body** = **`multipart/form-data`** (changed 2026-08-07, was JSON): the 30
  scalar fields from the supplied `api_data/new-api-ploan.txt` curl as form
  fields, **plus `ndid_reference_id`** (2026-08-14) — 31 in all — plus **five
  file parts**.

**`ndid_reference_id`** is NDID's `reference_id` for the accepted identity
verification (`PLoanFlow.ndidReferenceId`, recorded by `ndid_verify_page` when
`GET /rp/verify/{ref}` reports ACCEPTED). It is the **only field on this payload
the backend can independently verify**, and it is here because of pentest
finding #11 — see **Step 6: NDID signing** for what it does and does not fix,
and note it is *not* proof of verification, only the handle for obtaining proof.
It is the one field in **snake_case**; that is the name the API asked for.

**The file parts** (`PLoanContractSubmission.files`):

| Part field | Count | Source | Type |
| --- | --- | --- | --- |
| `cardIdImage[]` | **2** | `PLoanPhoto.idCard` — the ID-card photo (`card_id.jpg`), **then** `PLoanPhoto.selfieWithIdCard` — the selfie (`customer.jpg`) | `image/jpeg` |
| `documentImage[]` | **3** | the contract PDFs from `/pdf/loan` the customer consented to (`request.pdf`, `receipt.pdf`, `agreement.pdf`, in screen order) | `application/pdf` |

⚠ **There is no `customerImage` part any more** (changed 2026-09-02 on
instruction). Both identity photos ride `cardIdImage[]`, so **order is the only
thing that tells them apart** — ID card first, selfie second — with the
filenames as the only other hint. If the server ever needs them separated
again, that ordering is the contract to preserve.

The **slot names stay three**, though: `PLoanContractSubmission.fileFieldNames`
is still `cardIdImage` / `customerImage` / `documentImage`, because a refusal
has to say *which photo* is missing and a shared wire field can't. Reporting
therefore keys off the slot, not off what went out — `test/
p_loan_submission_test.dart` pins both one-photo cases so a shared field can
never hide a missing one. `customerImage` also remains a real group in
`imageGroups` (the regmast view) and in `submit_form/`, which is unaffected.

**The upload goes direct through `package:http`, bypassing the host bridge**
(`bypassHostBridge: true`, added to `sendMultipartGroupsApiRequest` for this).
That is what makes multipart affordable here and it is worth understanding: the
`httpMultipart` bridge handler exists because the **old**
`<:8082>/SavePloanContract` sent no CORS headers, so a browser upload was blocked
outright. `/ploan` is on the mobile API base, which answers
`access-control-allow-origin: *` — the same reason `sendMultipartApiRequest`
already uploads the ID card directly. So this needs **no host change and no app
release**, and works in the host and a plain browser alike. Outstanding #2 stays
closed.

⚠ **The `[]` suffix on the repeated fields is an assumption, not a spec.** There
is no documentation for these parts yet; it follows `regmast_ploan.php`, which
is where the field *names* come from and which repeats every group that way.
Both fields carry more than one part now, so both are suffixed — the 2026-08-17
live submit only proved `documentImage[]`, so `cardIdImage[]` is **unverified**.
`PLoanContractSubmission._repeatedSuffix` is the one place to change it.

A file the flow never captured sends **no part at all** — an empty part reads as
a zero-byte file — and its slot name is reported in `unresolvedFields` instead;
`canSubmit` gates on all three anyway. An undecodable PDF is reported the same
way rather than throwing out of the mapper. The `data:application/pdf;base64,`
prefix live `/pdf/loan` returns is stripped before decoding (the mock fixtures
build bare base64), so both upload identical bytes.

The **other** photos (collateral, เล่มทะเบียนรถ, หน้าสมุดบัญชี) are still not sent:
`imageGroups` is the regmast view, not this endpoint's.

⚠ The request carries five files, so it is **large**. A timeout or a
request-size limit is the first thing to suspect if a submit that used to work
starts failing.

**A failed submit shows the whole response** (added 2026-09-02, prompted by an
HTTP **500**). The dialog used to say `ส่งคำขอไม่สำเร็จ (HTTP 500)` and nothing
else: `_refusalMessage` decoded the body, looked for an `error`/`message` key,
found none — a 500 is usually an HTML page or a stack trace, not this API's JSON
envelope — and **discarded it**. A gateway trace, an error page and an empty
body all rendered as that one sentence.

So every throw path now attaches `SrisawadApiException.details`
(`PLoanContractApi.failureReport`) and step 6's error dialog renders it under
the message with a **คัดลอก** button:

| Line | Why |
| --- | --- |
| `POST <resolved url>` | which gateway this build actually reached — a transport failure has nothing else |
| `HTTP <status>` / `transport error: …` | one or the other, never both |
| `sent: 31 fields, 5 file parts (N KB)` | counts, not values; the size is the first suspect on a large upload |
| `blank: …` | `unresolvedFields`, so a 400 can be matched to a missing one |
| response headers | direct-`http` path only — see below |
| **response body, verbatim and untruncated** | the point of the whole thing |

- **The body is never truncated or summarised.** On a 500 the cause is often the
  last line of a long page, which is exactly what a cap would remove. A test
  pins this (`test/p_loan_contract_api_test.dart`), as it is the one property
  that would silently undo the fix.
- **It is non-prod only**, like `EnvVersionTag` and the diagnostics sheet: a
  gateway stack trace is what a developer needs and what a customer must not
  read. The customer-facing `message` is unchanged either way.
- **`ApiHttpResult` now carries `headers`** — filled on the direct
  `package:http` path, empty from the host's `httpRequest`/`httpMultipart`
  bridge, which answers `{status, body}` only. The report says *"(none — the
  host bridge does not return them)"* rather than printing an empty list, since
  "not available here" and "the server sent none" are different findings. This
  is the same limitation behind the NDID 429 backoff using a fixed delay instead
  of `ratelimit-reset`. `/ploan` always takes the direct path
  (`bypassHostBridge: true`), so in practice they are there.
- A **bounded** one-line excerpt (160 chars, whitespace collapsed) also goes to
  `Diagnostics.log`, so the trail behind the `(UAT ver…)` tag still says
  something once the dialog is closed. Bounded because that trail is persisted
  to `SharedPreferences` on every crumb.

⚠ It can contain personal data — same rule as `Diagnostics.report`. The bearer
token is not in it, but the response body is whatever the server sent.

This **deleted** `kPLoanSaveApiBase` (`:8082`) and `kPLoanSaveApiAuth` (the Basic
credential) from `app_environment.dart` — the pentest's high-severity
baked-in-credential finding is closed, since a bearer token replaces it. It also
removes the old host-side prerequisites: `httpMultipart` bridge handler and
`:8082` allowlist entry are no longer needed (see Outstanding #2).

⚠ **One backend fact still to confirm with a live submit:** that `<:7076>/ploan`
is reachable and that it sends `access-control-allow-origin: *` like the rest of
the mobile API (expected, since it is the same gateway — the sample curl doesn't
prove CORS). If it does, this flow now completes in a plain browser too, not just
in the host.

`PLoanContractSubmission.fromFlow(flow)` builds it — a **second** mapper beside
`PLoanSubmission`, because the field set is close to `regmast_ploan.php` but not
the same:

| | `PLoanSubmission` (regmast) | `PLoanContractSubmission` (save API) |
| --- | --- | --- |
| Customer name | one `test` field | `firstName` + `lastName` |
| Account holder | — | `bankAccName` |
| Branch | `branchID` | `branchId` (lower `d`) |
| Not sent | — | `transNo`, `transDate`, `payDay`, `initialDate`, `lastPeriodPromo`, `remark` |
| NDID | — | `ndid_reference_id` |
| Files | 12 multipart groups | 2 fields / **5 parts** |
| Count | 34 | 31 form fields + 5 file parts |

Shared values are **read back from `PLoanSubmission`** rather than re-derived, so
the two payloads can't disagree about the same number; a test asserts every
shared key matches, that `fields` is exactly the 30 from the API's own sample
(`api_data/new-api-ploan.txt`) plus `ndid_reference_id`, and that `files` is
exactly the five parts in order. The two sets are kept **separate** in
`test/p_loan_submission_test.dart` (`_saveApiFields` / `_saveApiNdidFields`) so
the sample's own 30 stay pinned as the sample's and any later addition reads as
an addition.

**Transport.** The body is `multipart/form-data` again (2026-08-07) — but for a
different reason than the old endpoint's, and with none of its cost. What made
`<:8082>/SavePloanContract` need the native host (verified 2026-07-27) was never
multipart as such: it was **no CORS headers and a 401'd preflight**, which
blocked a browser upload outright and left the never-built `httpMultipart` bridge
handler as the only route.

`/ploan` is on the mobile API base, which sends `access-control-allow-origin: *`.
So `PLoanContractApi` calls `sendMultipartGroupsApiRequest(...,
bypassHostBridge: true)` and uploads with `package:http` **directly, even inside
the host** — exactly what `sendMultipartApiRequest` already does for the ID-card
upload. The `httpMultipart` handler stays unnecessary.

That flag is the load-bearing part: without it that helper prefers the bridge,
and inside the host the submit would fail on a handler that does not exist. Set
it only for hosts that send CORS — never the NDID gateway.

**No credential ships in the bundle any more.** The old Basic service account
(`kPLoanSaveApiAuth`) was deleted with the retarget — `/ploan` authenticates with
the customer's own Firebase bearer token, so there is nothing shared to leak.
This closes the pentest finding it was flagged for. (The token still travels in
the launch URL — Outstanding #19 / App Check is the remaining hardening there.)

**`latitude` / `longitude` come from the device GPS** (added 2026-08-07).
`services/device_location.dart` is a conditional import over
`navigator.geolocation`; step 6's `initState` fires an **un-awaited**
`_captureLocation()` and writes the fix onto the flow, formatted to seven
decimals like the API's own sample.

**No host change was needed**, which is why there is no `getLocation` bridge
handler: the srisawad host already sets `geolocationEnabled: true`, answers
`onGeolocationPermissionsShowPrompt` with `allow: true, retain: true`, and
declares the Android/iOS location permissions (verified 2026-08-07 in
`loan_universal_web_widget.dart`). Adding a handler would have cost an app
release to reach what the web API already does — and it works in a plain browser
too.

It is captured on the **submit screen and never awaited**. The customer spends
minutes there (three PDFs, ID photo, selfie, NDID), so a fix that takes seconds
is long in place before ยืนยัน; awaiting it at submit would put a permission
prompt and a cold GPS lock in front of the one button that matters. A denial,
timeout or missing fix is silent by design — the fields stay empty, get reported
as before, and the application still files. The reason is logged to the WebView
console.

**Five fields are sent blank on purpose** (`PLoanContractSubmission.acceptedBlank`,
decided 2026-08-07): `gpsProvinceId`, `gpsAumphurId`, `empId`, `mktChannel`,
`customerSource`. They are always **present** as form fields with an empty value
— never omitted — and are no longer listed in `unresolvedFields`, because for
these five blank is the intended answer rather than a gap: the two gps ids need
a reverse lookup from lat/lng into srisawad's own id set that no endpoint here
provides, and the other three are host launch params a customer-initiated
application simply has none of.

⚠ It is "blank is acceptable", **not** "always blank" — a value the host does
pass in `?empId=…` is still read and sent. `empId` was also dropped from
`PLoanContractApi._expectedNonEmpty` so a refusal can't name a field that is
empty by design.

**Still reported when empty**: `creditAmt` for a new loan, `branchID`/`branchId`
for a new loan, and the three file fields. On a refusal the client appends the blank ones to the
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
- **Closing the sheet now closes the document** (fixed 2026-08-17). `pdfx` 2.9.2's
  `PdfController.dispose()` disposes only its `PageController` — it **never calls
  `PdfDocument.close()`** — so the pdf.js `PDFDocumentProxy` and its `ArrayBuffer`
  stayed alive in the JS heap and the worker for the rest of the session. Step 6
  requires all three contracts to be opened before the NDID row unlocks, so that
  left **three** orphaned documents resident from step 6 onward, through the whole
  NDID countdown. `_PdfInlineViewState._release()` now disposes the controller,
  closes the document, and clears the global `ImageCache` — `PdfView` rasterises
  every page at 2x as a JPEG through `PdfPageImageProvider`, so those bitmaps
  outlive the sheet inside a 100 MB budget. Clearing the whole cache is
  deliberately broad and cheap: the only other images this app caches are the
  ID-card/selfie thumbnails, which re-decode from bytes still held on the flow.
  ⚠ **This was not the white screen's cause** (see **On-device diagnostics**) —
  it was found while hunting it, and is a real leak either way.

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

> **Retired 2026-07-31: the non-prod test-identity substitution.** `kNdidTestThaiId`
> / `AppEnvironment.ndidThaiIdOverride` made non-prod builds ask NDID about
> `1234567890123` instead of the customer. All of it is **deleted** — not
> defaulted to empty — and `--dart-define=NDID_TEST_THAI_ID` is ignored.
> **Don't reintroduce it**; why it existed is in
> [docs/HISTORY.md](docs/HISTORY.md#ndid-test-thai-id).

What that changes for testing: a customer who has not onboarded with any IdP now
gets an **empty registered grid** — `ndid_bank_select_page` renders
"ไม่พบผู้ให้บริการที่ท่านเคยลงทะเบียน NDID" — rather than a usable mock bank. That
is the node answering truthfully. Since 2026-08-04 the **not-registered grid is
selectable**, so such a customer is no longer stuck: they can pick an
unregistered provider and register with it in the bank's app as part of the
verify hop. To exercise the fast (already-registered) path, still pick a test
customer who *is* onboarded.

`isThaiIdVerified` still compares the scanned card to `customer.thaiId` and
**not** to `ndidThaiId`; the two now coincide, but a test pins them as separate
concerns (NDID asserts "this person authenticated", the card check asserts "this
card is theirs"). No payload carries `ndidThaiId`. The wizard's
`LoanRegisterForm.ndidThaiId` was never overridden and still just strips its
formatted `thaiId` to digits — which is the **real** customer's id whenever step 1
was seeded from the profile.

Two deliberate differences from step 4:

- It enters the NDID sub-flow at `ndidTerms` like the wizard does, but skips
  the wizard's `document_review_page`. That screen exists to show the contract
  documents before signing, and step 6 already does — with the real PDFs from
  `/pdf/loan` instead of the wizard's mock list. So the gate here is the
  document consents: tapping the row before all three are accepted says so.
  Read, then sign.
- **ดาวน์โหลดเอกสาร actually opens the PDF** (`pdf_opener.dart`), where the
  wizard's equivalent is a stub SnackBar — that flow has no documents to open.

Note this is distinct from the ID-card block above it: that is KYC on a photo
(`/vision/thai-id-validate`), this is the customer signing the contract with
their bank identity. Both are required. `eSignatureImage` stays empty because
NDID produces a verification reference, not an image.

**The NDID reference reaches the submit payload** as of 2026-08-14:
`PLoanFlow.ndidReferenceId` — NDID's own `reference_id` for the accepted
verification — goes to `POST /ploan` as **`ndid_reference_id`**. Before that,
*nothing* about the NDID result was sent, which is what made pentest **finding
#11** ("Client-Side NDID Verification Response Tampering") more than cosmetic:
the tester flipped `status` to `"ACCEPTED"` in the polling response and the
application filed, because the only thing asserting verification was
`ndidVerified` — a client bool — and the server had no way to check.

Three things to keep straight about it:

- **The reference is what the server can verify; `ndidVerified` is not.** That
  bool is worth exactly what any client bool is worth. Sending the reference is
  what makes a real check *possible* — it does not perform one. **Finding #11
  stays open until `/ploan` confirms the reference with NDID server-to-server**,
  binds it to the caller's own citizen id, and refuses a reused one.
- **It is written only on the real API path** (`ndid_verify_page.dart`, when
  `GET /rp/verify/{ref}` reports ACCEPTED). The plain-browser
  "จำลองยืนยันตัวตนสำเร็จ" hop records **nothing**, on purpose: inventing a
  reference would claim a verification that never happened. So a simulated flow
  sends the field blank and it lands in `unresolvedFields` —
  ⚠ which also means that button remains a genuine bypass of the NDID step in
  any build a browser can reach (see **Outstanding**).
- **`ndid_reference_id` is snake_case** where the other 30 form fields are
  camelCase. That is the name the API asked for, so it is sent verbatim rather
  than normalised to match its neighbours.

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

Verified against the uat mobile API (`https://dev.swpfin.com:7076` at the time;
the uat config has since moved to `https://srisawad-qa.ecorpgroup.com` — see
**Runtime config from Firestore**). The behaviours below are the API's, not a
particular host's:

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
`AppState.appConfig`. Verified working on uat.

⚠ **Read the document rather than trusting a value written down here.** Both
endpoints are editable in Firestore with no rebuild, and both have moved. As of
2026-09-11 the uat document holds:

| key | value | read by |
| --- | --- | --- |
| `api_url.api_url_prod` | `https://mobile-api.swpfin.com` | prod builds |
| `api_url.api_url_dev` | `https://srisawad-qa.ecorpgroup.com` | uat builds |
| `api_url.api_url_base` | `https://srisawad-qa.ecorpgroup.com` | fallback only |
| `api_url.ndid_url_base` | `https://ndid.srisawadpower.com` | prod builds |
| `api_url.ndid_url_base_uat` | `https://uat.ndid.srisawadpower.com` | uat builds |
| `topup_product_icons` | product-code → SVG URL, for the top-up card's offer tiles | both (`…_uat` overrides) |
| `topup_product_icon_default` | fallback icon URL | both (`…_uat` overrides) |

| `ndid_as_id_uat` | `A18AC373-9CCB-47B3-A285-9ADBA29AFEFC` | uat builds — pins the AS, see **NDID API client** |

Every key above takes a `_uat` variant; `topup_product_icons_uat`,
`topup_product_icon_default_uat`, `ndid_request_type_uat`, `ndid_as_id` (prod)
and `ndid_as_name`/`_uat` are supported and currently unset — for the icons
because both environments want the same values, and for `ndid_as_id` because
prod should resolve its AS rather than pin one.

⚠ **`https://dev.swpfin.com:7076` no longer serves** (confirmed 2026-09-11).
`AppEnvironment.uat.mobileApiBase` was still pointing at it, which meant any
failure to read the config — denied rule, failed anonymous sign-in, Firestore
unreachable — degraded the app onto a **dead gateway**. Now
`https://srisawad-qa.ecorpgroup.com`, matching the document. A fallback is only
worth having if it works.

That divergence is still worth understanding, because it will recur whenever
the config moves: the compile-time default is only the degrade-to value, so
**what the app actually calls is the config's host**. A request reproduced by
hand against the wrong host is not hitting the same gateway the app is — check
the resolved endpoint `main.dart` logs at boot, labelled `(config)` or
`(default)`, before concluding a payload is at fault. That is exactly how a
`POST /payment/interest` "500" turned out to be a retired host rather than a
bad body.

**Environments are separated by field name.** `AppConfig.envValue` reads
`<key>_uat` on a uat build and the bare `<key>` on prod, matching the
`sawad_loan_universal_version` / `…_version_uat` pair the host app already
uses — so the same convention spans both projects. It applies to everything
resolved through `urlFor`, which is every endpoint below.

⚠ uat **falls back to the bare key** when no `_uat` variant exists. That keeps
a document predating the convention working and lets `_uat` keys be added one
at a time; the cost is that a *shared* document carrying only bare keys gives
uat the prod value. Safe today because the environments are also separate
projects — but it is the first thing to check if a uat build ever reads a prod
endpoint.

The one exception is the mobile API, which keeps its original
`api_url_prod` / `api_url_dev` spelling rather than moving to the `_uat`
suffix: both keys already exist under those names in both documents, and
renaming a live key to tidy a convention is how an environment ends up on the
wrong gateway.

**Two endpoints now come from this document**, both by the same rule — config
value first, compile-time define as the degrade-to:

| `api_url` key | Read by | Falls back to |
| --- | --- | --- |
| `api_url_base` (then `api_url_prod`/`api_url_dev`) | `SrisawadApi.baseUrl()` | `AppEnvironment.mobileApiBase` |
| `ndid_url_base` | `NdidApi.baseUrl()` | `kNdidApiBase` |

`AppConfig.urlFor` trims and strips a trailing slash for both, so a value saved
as `https://host/` can't produce `//idp/list`. Any other key in the map is
reachable through `urlFor` without a code change.

- ⚠ **The config read and its sign-in deliberately bypass the host bridge**
  (`bypassHostBridge: true`, added 2026-07-31). This is the fix for a bug worth
  understanding, because the failure mode was **silence**: `sendApiRequest` routes
  everything through the host's `httpRequest` handler when
  `NativeCameraBridge.isSupported`, and that handler only calls allowlisted
  prefixes — which never included `firestore.googleapis.com` or
  `identitytoolkit.googleapis.com`. So **inside the app the config had never
  loaded at all**: sign-in was rejected, `idToken()` returned null, `AppConfig`
  resolved empty, and every caller silently used its compile-time endpoint.
  Nothing looked wrong for days because uat's `api_url_base` *equals*
  `AppEnvironment.uat.mobileApiBase`. It only surfaced when `ndid_url_base` named
  a **different** host and the NDID bank grid kept showing the old DAP node's
  `idp1/idp2/idp4`. Google's APIs are CORS-enabled (their preflight allows the
  `authorization` header — verified), so a direct fetch is the right transport and
  needed no app release. **Never set that flag for the NDID gateway or the P-Loan
  save API** — neither sends CORS headers, so for those the bridge is the only
  way. `main.dart` now also logs the **resolved** endpoints with a
  `(config)`/`(default)` label, which is what would have caught this on day one.
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
| `topup_api.dart` | `TopupApi` — the single seam the **top-up flow** talks to: `/topup/detail`, `/topup/calculator`, `POST /topup`, `/topup/status-detail`, `POST /payment/interest`, the lead fallback, and thin delegates to `PLoanApi` for the product-neutral `/pdf/loan` + `/vision/thai-id-validate` |
| `p_loan_api.dart` | `PLoanApi` — the single seam the P-Loan flow talks to. Delegates the three shared calls to `TopupApi`; owns `/pdf/loan`, `/vision/thai-id-validate`, and `calculateNewLoanInstallments` (interim client-side estimate for a new P-Loan) |
| `p_loan_contract_api.dart` | `PLoanContractApi` — `POST /ploan`, the **P-Loan save API** (mobile API base, **bearer** auth, JSON). Reached via `PLoanApi.savePLoanContract` |
| `user_api.dart` | Customer profile + address book |

**Base URL resolution order** (`SrisawadApi.baseUrl()`), changed 2026-09-11:
`api_url_prod` (prod build) / `api_url_dev` (uat build) → `api_url_base` →
`AppEnvironment.current.mobileApiBase`.

⚠ **`api_url_base` used to be preferred and no longer is.** The old reasoning
was that it is per-project, so each project's copy holds its own host. That
holds only as long as nothing else reads the document: it **names no
environment**, so it cannot express the difference, and a document serving both
would hand uat the prod host. Environments are now separated by **field name**,
not only by living in separate Firebase projects. `api_url_base` stays as the
fallback for a document carrying neither of the pair. Trailing slashes are
stripped, so a value like `https://mobile-api.swpfin.com/` won't produce `//`.

`NdidApi.baseUrl()` follows the same pattern against `ndid_url_base` — see
**NDID API client** — so the NDID gateway is not in the table above but is
config-driven too.

**Every call on this base sends `Authorization: Bearer <token>`** — the
customer's Firebase JWT from the `?token=` launch param — alongside
`x-srisawad`. Both come from `SrisawadApi.headers(token)`, which is the only
place either header is built, and **`token` is a required argument on every
client method**, so the compiler is what guarantees it.

That last part was made true on 2026-08-14, and it is worth knowing why.
`headers()` was always correct; what went wrong was a caller.
`UserApi.fetchUserDetail(hash)` simply **had no token parameter**, so
`GET /user/detail` — a customer's own profile, keyed only by `hash_thai_id` —
went out unauthenticated from all three of its call sites (startup in
`main.dart`, P-Loan step 1, `/pLoan/resume`). That is the endpoint **pentest
finding #2** ("Improper Access Control: Authenticated API could be accessed
without authentication") names first. Every other endpoint on the base already
passed a token.

Two things stop it recurring rather than just fixing the one call:

- `token` is `required` on `fetchUserDetail`, `fetchAddressBook` and
  `PLoanApi.fetchCustomer` — an optional one let `?? ''` stand in for a real
  credential, which is the same omission wearing a default value;
- an **empty** token still sends no `Authorization` header (a bare `Bearer `
  looks authenticated in a capture while granting nothing) but now **prints a
  warning** to the WebView console naming the missing `?token=`. Silence is what
  let the gap sit unnoticed. `test/srisawad_api_headers_test.dart` pins the
  header contract.

⚠ **Consequence for testing:** opening a build with `?hashThaiId=` but **no**
`?token=` now gets a 401 on `/user/detail` instead of a profile. The wizard
degrades as designed — the startup fetch logs and swallows, step 1 keeps
persisted/mock data — but P-Loan step 1 and `/pLoan/resume` show the API's
error. Always pass `&token=<JWT>`, which the browser-testing recipe above
already does.

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

### Top-up flow (`lib/topup/`)

**A 6-step wizard**, ported from LandAndHouseWeb's `lib/customer_topup/`
(entry `TopupCardPage`). Added 2026-09-11.

⚠ **There is no วัตถุประสงค์ step** (removed 2026-09-11, was step 2). The
contract card already settles which product a request is for, so a screen that
asked again could only repeat the answer:

| Tapped on the card | Result |
| --- | --- |
| **เติมวงเงิน** | a plain top-up — `purpose` stays null and the amount is editable |
| a **สิทธิพิเศษเฉพาะคุณ** tile | that product's code and price ride onto the flow, fixing the amount |
| the **`PLD001`** tile | leaves for the P-Loan Extra flow entirely — different product, different endpoint |

`TopupPurpose` survives as the value the card constructs; nothing renders a
list of them any more.

⚠ **The card shows no step indicator**, so the bar first appears on the amount
screen at **2 of 6**. The card is still *counted* as step 1 rather than the
wizard renumbering from the amount screen: it is where the product is chosen,
so dropping it from the count would disown the screen the customer just used —
the same reasoning as `PLoanEntry.precedingSteps`.

**Two entry points:**

| From | How |
| --- | --- |
| this app's home menu card **สินเชื่อเพิ่ม** | `context.push(AppRoutes.topupCard)` |
| the srisawad app's home menu **เติมวงเงินใหม่** | `/loan-universal-webview` with `path: '/topup'`, `params: {'fromHost': 'true'}` |

The second was added to the host on 2026-09-11
(`lib/pages/home_page_component/home_page_options.dart`, branch
`pentest_resolved`) and is **QA-only**, behind `_showTopupNew =
FlavorConfig.isQa`. It uses the same host mechanism the `PLD001` chip uses to
reach `/pLoan/resume`, so no route or widget changed there.
⚠ Like every host edit, it **needs an app release to reach testers** — a web
deploy of this repo cannot carry it (same constraint as Outstanding #10).

`fromHost=true` is what tells `TopupCardPage` that nothing sits beneath it on
this build's own stack, so its back button calls `closeWebview()` instead of
navigating to this build's home — and the success screen does the same.

`/topup` also accepts `?source=&referId=&contNo=` (attribution, and a contract
to preselect).

⚠ **A top-up is not a P-Loan Extra, and this is the thing to get straight
before editing either.** They look alike and price differently:

| | Top-up (`lib/topup/`) | P-Loan Extra (`lib/p_loan/application/`) |
| --- | --- | --- |
| What it does to the old contract | **closes it out** and reissues it larger | only **references** it |
| Payout | `requested − closing_balance − duty` | `requested − duty` |
| `min/max_topup_amount` | **apply** | deliberately ignored |
| Amount | customer chooses, within the range | fixed at `topup_extra` |
| `interest_paid_flag == 'Y'` | locks the field → pay interest first | not a factor |
| Submits to | `POST /topup` | `POST /ploan` |
| NDID signing | none | required |

The two flows are **separate page sets** on purpose. They share the models,
services and the `p_loan_components` kit — those are product-neutral — but not
their screens, so the live, pentested, NDID-reviewed P-Loan flow was not
touched to add this.

Screens (`TopupStepIndicator` counts 1–7):

| # | Page | Title | Calls |
| --- | --- | --- | --- |
| 1 | `topup_card_page` | สินเชื่อเพิ่ม | `/user/detail`, `/loan/list` |
| 2 | `topup_amount_page` | ยอดสินเชื่อที่ต้องการ | `/topup/detail`, `/topup/calculator` |
| 3 | `topup_installment_page` | เลือกจำนวนงวด | — |
| 4 | `topup_photos_page` | **ข้อมูลการต่อภาษี** | `image_picker` (**not** the bridge — see below) |
| 5 | `topup_customer_data_page` | ตรวจสอบข้อมูลส่วนตัว | `/profile/address/{hash}` |
| 6 | `topup_conclusion_page` | สรุปรายละเอียดสินเชื่อ | `/pdf/loan`, `/vision/thai-id-validate`, `POST /topup` |
| — | `topup_success_page` | (terminal, both endings) | — |
| — | `topup_status_page` | สถานะคำขอ | `/topup/status-detail` |
| — | `topup_qr_payment_page` | ชำระด้วย QR | `POST /payment/interest` (made on step 3) |

`TopupFlow` (`models/topup_flow.dart`) is the mutable state passed page → page
as go_router `extra`, same convention as `LoanRegisterForm` / `PLoanFlow`.
Steps 2–7 redirect to step 1 without one; `topupStatus` and `topupSuccess`
carry everything in the query string instead, because both are reachable
without a flow (a link from the contract card, and a reload after submitting).

**Step 3's button does one of three things** (`TopupFlow.outcome`) — this is
the flow's central rule, and it is the source's, kept verbatim:

| Outcome | When | Button |
| --- | --- | --- |
| `payInterest` | `interest_paid_flag == 'Y'` | **ชำระเงิน** → `/payment/interest` → the QR screen |
| `lead` | `loan_type_code` is `L`/`H`, **or** `can_topup != 'Y'`, **or** `netTransferAmount > max_transfer_amount` | **ส่งข้อมูล** → files a lead |
| `topup` | otherwise | **ถัดไป** |

⚠ **An absent `max_transfer_amount` reads as 0, and 0 refuses everything** — no
positive payout is under it, so *every* contract files a lead. Reproduced from
the source and pinned by a test, because it looks exactly like a bug. If the
flow suddenly offers ส่งข้อมูล for every contract, the field is missing from
`/loan/list`. It is deliberately **not** treated as "no limit": guessing the
cap open would let through a request the backend meant to hold back.

**Three payout figures, deliberately not merged.** The source really does
compute three different numbers, and collapsing any two changes either what is
filed or what the customer is promised:

| Getter | Is | Used by |
| --- | --- | --- |
| `payoutAmount` | `amount − closing_balance − fee` | `transfer_amount` on the submit body; deduction item 3 |
| `receivableAmount` | `payoutAmount − overdueDeduction` | **`จำนวนเงินที่จะได้รับ`**, the figure on screen |
| `netTransferAmount` | `payoutAmount − yield − collection_fee` | the lead-branch eligibility test only |

⚠ The collection fee comes off `netTransferAmount` **unconditionally** but off
`receivableAmount` only as part of item 5 (i.e. only when there is unpaid
interest). That asymmetry is the source's, reproduced deliberately and pinned
by a test.

**The amount screen's deductions are a numbered list** (`deductionLines`),
matching the source's layout:

| # | Row | Shown when |
| --- | --- | --- |
| 1 | หักยอดเงินต้นคงเหลือสัญญาเก่า | always |
| 2 | หักอากรสแตมป์ | always |
| 3 | จำนวนเงินก่อนจ่ายยอดค้างชำระ | unpaid interest |
| 4 | ยอดค้างชำระงวดที่ (`overdue_to`-`overdue_from`) | unpaid interest **and** `overdue_amount != 0` |
| 5 | รวมหักดอกเบี้ยและยอดติดตามทวงถาม (+ 5.1 ดอกเบี้ย, 5.2 ค่าติดตามทวงถาม) | unpaid interest |

⚠ **The on-screen numbering really does skip 4**, because item 4 needs a
non-zero overdue amount and item 5 does not, so the list commonly reads
1, 2, 3, 5. The numbers are fixed labels, not positions — renumbering them
would make this build disagree with every QA screenshot. A test pins it.
(The user manual calls this out too, as note A6.)

⚠ **`interest_paid_flag == 'Y'` means interest is *outstanding***, despite how
the name reads. Both item 4 and item 5 render on `== 'Y'`, and the amount
field locks. The user manual's §2.2 prose says the opposite ("shown when
interest_paid_flag is not 'Y'") — that prose is **wrong**; its own mapping
table and the source code both say `== 'Y'`.

**`topup_special_flag`.** When the contract carries it, `topup_specials` is
granted **on top of** the ordinary limit and `GET /topup/detail` does **not**
include it — so `TopupFlow.applySpecialLimit` raises `default_topup_amount`
*and* `max_topup_amount` client-side, between the detail call and the first
calculator run. Without that the uplift the card advertised is offered nowhere.
`LoanContract.topupSpecialFlag` was added for this (additive; P-Loan ignores it).

**The duty is the calculator's.** Step 3 folds `plan.feeAmount` back in with
`detail.copyWith(feeAmount: …)` — same rule the P-Loan flow follows and for the
same reason: `/topup/detail` returns the duty on the contract's *default* limit,
`/topup/calculator` on the amount actually requested.

#### Section inventory (against the QA user manual)

The screens are built to match **`LandAndHouseWeb/docs/topup-user-manual-v2.md`**
(+ its `screenshots/`), which is the reference for what each one must carry.
Sections present:

| Manual | Screen | Carries |
| --- | --- | --- |
| §1.2 | card | วิธีขอปรับวงเงินเพิ่ม conditions panel, contract pager, swipe hint |
| §1.3 | card | **สิทธิพิเศษเฉพาะคุณ** product grid, when the contract carries add-on products |
| §1.3 | card | รับเงินโอนเข้าบัญชีสูงสุด band; credit summary — วงเงินสินเชื่อเดิม, ราคาประเมินหลักทรัพย์ปัจจุบัน, วงเงินสินเชื่อปัจจุบัน, ยอดปิดบัญชี ณ วันที่ (`data_date`), เงินคงเหลือโอนเข้าบัญชี |
| §2.1/2.2 | amount | amount field + slider + min/max, the numbered deduction list (see above), จำนวนเงินที่จะได้รับ, ชำระเงิน / ปรับปรุงยอดชำระ |
| §2.3 | QR | amount due, payment-window note, QR, R1/R2, bank exclusions, ปรับปรุงยอดชำระ |
| §3.1 | installments | ยอดจัดสินเชื่อใหม่ + tenor list |
| §3.2 | photos | ทะเบียนจังหวัด / วันหมดอายุทะเบียน / ยี่ห้อสินค้า / รุ่นสินค้า, then the required photos |
| §4.1/4.2 | customer data | account, name, phone, four addresses, ไม่ถูกต้อง / ยืนยัน, confirm sheet |
| §5.1–5.3 | conclusion | สรุปยอดสินเชื่อใหม่ (5 rows + payout), รายละเอียดคำขอสินเชื่อใหม่, identity photos, three document consents, PDPA |
| §5.4 | success | payout + deadline caveat, ดูสถานะการขอเพิ่มวงเงิน, กลับสู่หน้าแรก |

⚠ **`บันทึกรูปภาพ` (save the QR image) is deliberately left out.** The source
saves it through a native custom action this build has no equivalent for, and a
web `<a download>` inside the WebView is not reliably honoured — a button that
silently does nothing is worse than no button. The payment payload can be
copied instead, and a screenshot works. Add it back only alongside a host
handler that actually saves.

#### The 2026-09 redesign (card + amount screens)

**The card and amount screens were rebuilt to a BA design** on 2026-09-12,
from `etc/M35 + หน้าจอเติมเงิน_ปิดปรับผ่านแอพมือถือ_หลั.pdf` (git-ignored).
The rest of the flow — installments, photos, customer data, conclusion,
success, status, QR — is untouched.

**The pre-redesign screens are preserved**, routed at **`/topup/old`** and
**`/topup/amount-old`** (`topup_card_page_old.dart` /
`topup_amount_page_old.dart`), each carrying a banner saying it is superseded.
They share **nothing** with the redesign — not even a helper — so editing the
new screens cannot change what they render. ⚠ Delete the pair together once
the redesign is signed off; they are a comparison aid, not a fallback.

Shared pieces live in **`components/topup_redesign.dart`**: `TopupTheme`,
`formatTopupMoney`, `TopupFigureRow`, `TopupDottedDivider`, `TopupStatusPill`
and `TopupContractHeader`.

⚠ **This page family carries its own palette** (`TopupTheme`), like the QR
screen and for a related reason: the design is the BA's, handed over as
renders, and its band blue is not `LoanRegisterStyles.value`. Matching the
approved renders beat matching the rest of the app; **that trade does not
generalise** — don't copy the pattern onto another screen.

⚠ **`formatTopupMoney` always renders two decimals**, where the old screens
round to whole baht in places. It has to: both screens show a subtotal, two
deductions and a result, and rows that round independently stop adding up. A
reader who sums three rows and gets a different total has found a bug in the
app, not in their arithmetic.

**Two model changes were prerequisites**, both with effects beyond the UI:

- **`closing_balance` is a `double`.** Parsed as `int` it truncated `86217.08`
  to `86217` — the same defect `yield`/`collection_fee`/`penalty_fee` carried
  until 2026-09-11, with the same two effects: a figure misstated on screen and
  a changed `transfer_amount` on the submit body. `TopupFlow.closingBalance`
  and `payoutAmount` widened with it.
- **M35 is `topup_extra`**, not `topup_specials` (instructed: *"วงเงินพิเศษ M35
  -> is topup_extra"*), via `TopupFlow.specialLimitOf`. ⚠ **`topup_special_flag`
  is no longer the gate** — a non-zero amount is; that flag belonged to
  `topup_specials`, so requiring it would hide money the backend granted.
  ⚠ **The same field is a P-Loan Extra's entire request amount**
  (`LoanAmountDetail.extraRequestAmount`): one number, two products. Nothing
  needs to reconcile them — the card's PLD001 tile leaves this flow — but don't
  read one as evidence about the other. Three tests pin the field, the dropped
  gate, and that `topup_specials` alone no longer uplifts anything.

**The card** (PDF p.4): a blue ✨ ข้อเสนอพิเศษสำหรับคุณ band leading with the
payout, the contract block with a `ข้อมูลสถานะ` pill, a dotted rule, then
วงเงินสินเชื่อใหม่สูงสุด, เงินต้นที่ยังไม่ถึงกำหนดชำระ (−), อากรแสตมป์สัญญาใหม่
(−), the light-blue **เงินคงเหลือโอนเข้าบัญชีสูงสุด\*** strip, the red
`*เมื่อชำระยอดเพื่อเติมวงเงิน` note and the orange **เติมวงเงิน** button.

⚠ **The payout is computed, not read from `default_transfer_amount`.** That
field arrives **without the duty taken off** — verified against the
`GetRecalTopupData` sample: `88,500 − 86,217.08 = 2,282.92`, no fee. Three rows
above a total that disagrees with them is worse than either number alone, and
the computed value is the same formula `TopupFlow.payoutAmount` files as
`transfer_amount`. The band and the strip quote the **same** figure on purpose:
the band is the promise, the rows are the arithmetic behind it.

⚠ **The M35 uplift is visible as a bigger number, not different furniture.**
The card shows only the combined limit (PDF pp.10/11 differ solely in the
figures); the amount screen breaks it back out.

**The `can_topup = N` card is a separate build, not a variation** — it answers
a different question. Peach header, red warning glyph, *ขออภัย รายการนี้ยังไม่
สามารถทำผ่านแอปได้ / กรุณาติดต่อสาขาเจ้าของบัญชี หรือโทร 1652*, the
`⏱ ไม่เข้าเงื่อนไข` pill, and **วงเงินสินเชื่อเดิม** — the existing line, never
an offer above a refusal of it. **No button**: the action is a phone call.

⚠ **`Code : xxx` renders only when the API sends a code.**
`TopupDetail.canTopupCode` reads `can_topup_code`, falls back to a bare `code`,
and is **empty otherwise** — in which case the line is absent. No sample
response carries one, so **the wire name is unconfirmed**; point it at the real
key when the API team names it. A `Code :` with nothing after it tells a branch
less than no line at all.

⚠ **The conditions panel stays at the top of the page.** It briefly sat below
the cards so the screen would open on the offer the way the render does; that
was reverted on request the same day (2026-09-12). It is how a customer finds
out *why* a card says what it says, which is worth more than leading with the
number.

⚠ **Every text colour on these two screens comes from `TopupTheme`**, and there
are exactly four: navy value, grey label, orange primary, red alert. A one-off
teal caption on the product grid and the softer `LoanRegisterStyles.required`
red were both folded in — a fifth colour on one caption read as a different
kind of message than it was. `TopupNotice` gained an optional `accent` for
this, so a redesigned screen can use the design's pure red **without**
repainting the un-redesigned steps or the `_old` pair.

⚠ **`TopupConditionsCard` is a near-copy of `TopupConditionsPanel`**, and
deliberately so: the `_old` card page still renders the original, and the point
of the `_old` pair is that editing the redesign cannot change them. The
**wording is identical** and pinned by a test, since duplicated copy drifts.
Delete the original along with the `_old` pages.

**The amount screen** (PDF pp.5–7, 9–11): contract block (no status pill), the
M35 pair when there is one (`ยอดจัดสินเชื่อเดิม` + `วงเงินพิเศษเพิ่มเติม
+5,000.00` — the only figure on the screen that *adds*), the blue
**วงเงินสินเชื่อใหม่สูงสุด** bar, the orange **เงื่อนไข** note, the big
borderless amount field, the **เลื่อนเพื่อปรับลดวงเงิน** slider, the two หัก
rows and **เงินคงเหลือโอนเข้าบัญชี**.

⚠ **Two figure layouts, and which one a figure gets is meaningful.**
`TopupStackedFigure` puts the label on its own line with the amount large
underneath and its unit at the right margin; `TopupFigureRow` is the
label-left/value-right table row. Stacked is for anything read as a
*quantity* — the requested amount and the two figures the M35 limit is built
from. The row form is for the deduction list, where labels are long and the
figures are compared down a column. Set from the BA's screenshot on
2026-09-12: as table rows the M35 pair had long Thai labels squeezing the
figures they introduced, and read as entries in a list rather than as the
arithmetic behind the blue bar.

⚠ **`+5,000.00` is not orange.** It was, briefly. The screenshot draws the M35
pair as two readings of the same kind, and colouring one of them made the
uplift look like a separate offer rather than a term of the sum above the bar.
The `+` is what marks it.

⚠ **The เงื่อนไข note states the rounding rule** because the field enforces it
silently: typing `96,050` and being handed `96,000` back is otherwise
indistinguishable from the app losing the input.

**`ยอดที่ต้องชำระเพื่อเติมวงเงิน` is the server's breakdown**, from
`POST /GetRecalTopupData` — see that section. It is re-read on every calculator
run (it is priced per `topup_amount`), and the previous rows are cleared
**before** the call, never after: leaving the old amount's settlement under a
new figure would explain the wrong number.

⚠ **`TopupFlow.outcome` is still the authority for the buttons**, and the
breadth of that matters. It is what protects the unpaid-interest and lead
paths, and it works with **no** recalculation endpoint — which is the current
state, since a web build cannot reach one. The breakdown only ever
**upgrades**: rows to settle mean there is something to pay, so a contract that
would otherwise show **ถัดไป** gets the design's **ชำระเงิน** /
**ปรับปรุงยอดชำระ** pair instead. It never downgrades — a lead contract stays a
lead however the settlement reads, and unpaid interest still blocks with no
rows on screen.

#### The contract card has three headers

`TopupCardVariant.of(contract)`, in this order — a contract that is *both*
ineligible and carries products shows the ineligible header, not the offer:

| Variant | When | Shows |
| --- | --- | --- |
| `ineligible` | `topup_detail.can_topup == 'N'` | ยังไม่สามารถเติมวงเงินได้ในขณะนี้ / ติดต่อสาขาเพื่อขอคำแนะนำ. No amount, no action |
| `specialOffer` | the contract carries add-on products | ข้อเสนอพิเศษสำหรับคุณ (+ the special limit when there is one), then the ordinary card |
| `plain` | otherwise | the ordinary card |

Separately, the **สิทธิพิเศษเฉพาะคุณ** grid in the card body
(`showsSpecialOffers`) needs *three* conditions: products, `can_topup != 'N'`,
**and** no request already in flight — tapping a product starts a request, which
a contract mid-request cannot take. So the offer header can appear while the
grid is withheld; they are deliberately not the same predicate.

⚠ **An empty product entry does not count.** The API pads
`topup_detail.products`, and an entry with no code and no name must not flip the
card into its offer layout. `LoanProduct.isEmpty` is the filter, and a test pins
it.

⚠ **The source contains a dead copy of this chain guarded by `if (true)`**,
which always returns the plain header. It is a FlutterFlow leftover from a list
layout the carousel replaced, and reading it instead of the carousel's builder
is an easy way to conclude the variants do not exist. The live one is the
`loanListCarouselItemItem` builder.

**Tapping `PLD001` leaves the top-up flow.** That code is the **P-Loan Extra**
offer, a different product on a different endpoint, so the tile pushes
`/pLoan/resume?dbName=&contractNo=` — the same entry the LandAndHouseWeb card
reaches via `srisawad://ploan-extra` and the host's own chip reaches natively.
It is deliberately *not* carried through as a top-up purpose: a top-up closes
the contract out and reissues it larger and files with `POST /topup`, a P-Loan
Extra only references it and files with `POST /ploan`.
`TopupCardPage.pLoanExtraProductCode` is the constant.

**Tiles show the icon and the product name, nothing else.** The price is
deliberately omitted: it is the *product's* price, not what the customer
receives, and a second figure on a card whose other numbers are all payouts
invites reading it as one — the amount is settled on step 3. Its row was also
taking the space the name needed, which clipped `วงเงินเอนกประสงค์` to
`วงเงิน` on a real device (fixed 2026-09-11; `childAspectRatio` 1.2 → 1.0 as
well, so the two lines still fit on a narrow phone).

**Tile icons come from the runtime config**, `topup_product_icons` in
`application/public_config` — a map of product code → SVG URL, plus
`topup_product_icon_default`. Read through `AppConfig.topupProductIcon`, which
falls back default → null, and the tile falls back again to a built-in Material
icon, so a missing config or a failed fetch never leaves a broken image.

The URLs are the LandAndHouseWeb project's own, copied verbatim: public
Firebase Storage links in the **prd** bucket that answer
`access-control-allow-origin: *` (verified), so `flutter_svg` can fetch them
from the browser. Seeded into the uat document on 2026-09-11 with a
field-masked PATCH; ⚠ **prod's document has not been seeded** — do that before
the flow ships there, or every prod tile shows the fallback icon.

| code | icon |
| --- | --- |
| `PLD001` | shopping bag |
| `GLD001` | coins |

⚠ **The source's own lookup is broken, and this is worth knowing before
"fixing" ours to match it.** It stores two parallel arrays and its generated
record reads **`produce_code`** while the document stores **`product_code`** —
so `findIndexInList` returns -1 every time and *every* tile in the live app
falls back to the placeholder square. The real icons have never rendered there.
A code-keyed map cannot desync that way, which is why ours is one.

**The entry page scrolls as a whole**, not just the card. The card grew tall
(credit summary plus a product grid can exceed a phone screen) and a `PageView`
inside a scroll view needs a fixed height, which would either clip the tallest
card or leave a gap under the shortest. So the carousel is unrolled: one card
renders inline in a `ListView` and the pager moves between them, with a
horizontal drag keeping the swipe the manual describes.

#### Deliberate deviations from the source

Each of these is a behaviour change, not a port artefact:

- **The four hardcoded Thai IDs are not reproduced.** The source's ID check
  accepted `1103000101931` / `1103701967986` / `1331400042203` /
  `3401700351967` alongside the customer's own, which let anyone holding one of
  those cards verify for **any** account. Same decision the P-Loan port made;
  `test/topup_flow_test.dart` pins it shut.
- **The PDPA consents are real.** The source hardcoded `marketing_consent` and
  `sensitive_consent` to `'Y'` in the submit body, recording a marketing
  consent the customer was never asked for. Step 7 asks: ยินยอมข้อมูลอ่อนไหว is
  required and gates `canSubmit`, ยินยอมการตลาด is a genuine opt-in that gates
  nothing. `N` is a real answer, so neither is ever reported as unresolved.
- **No baked-in lead credential.** See **The lead fallback** below.
- **No Firebase Storage mirror.** The source uploaded every photo to Storage
  and threaded three parallel URL/file/base64 fields per slot through the page
  model — 21 fields for 7 photos, and a Firebase Storage dependency this app
  does not have. The bytes are what `POST /topup` wants; the Storage copy was
  never read back. Photos are held as raw bytes and base64-encoded once, at
  submit.
- **The purpose list is rebuilt, not appended to.** The source's
  `generateTopupProductListNew` appended "อื่นๆ" straight onto the contract's
  own `topup_detail.products`, so the list grew by one every time the screen
  opened. `TopupPurpose.forContract` builds a fresh list; a test pins it.
- **Errors keep the customer on the screen** with a retry, instead of the
  source's modal-then-pop, which left them with nothing to act on.
- **A loan type outside `M`/`C` stays completable** (tax disc only) rather than
  hitting the source's permanently-disabled confirm button. Same deviation the
  P-Loan port made.

#### The JS bridge replaces the console-log protocol

The source talks to the native host by **printing magic strings** and waiting
for a `CustomEvent` back. This port uses the `flutter_inappwebview`
`callHandler` bridge this repo already has (`services/native_bridge.dart`):

| Source | Here |
| --- | --- |
| `print("${action}CameraAction5544${type}")`, then a global `fromFlutterMobile` listener carrying `{dataBase64, actionName}` | `await NativeCameraBridge.captureDocument(action)` — the promise resolves with the image |
| `print("CloseWebviewPageFromVolley5544Web")` | `NativeCameraBridge.closeWebview()` |
| `print("DoneLoadingVolley5544Web")` / `returnTextToApp` | not needed — nothing polls for readiness |

The difference that matters: `callHandler` returns a promise, so a capture is
just an awaited result. There is no global listener, no correlation by action
name, and a cancel is `null` rather than silence.

⚠ **`TopupPhoto.cameraAction` strings are not free-form.** The host branches on
`action.toLowerCase() == 'selfie'` and falls through to the rear ID-card mask
for **everything else**, so a near-miss fails silently with a wrong-looking
camera rather than an error. That exact bug cost the P-Loan flow its front
camera once; a test pins the selfie slot's string.

**Which is why step 5 does not use the bridge at all** (changed 2026-09-11).
That same fall-through means the host puts an **ID-card framing mask** over a
whole vehicle, a tax disc and an odometer, and it cannot be taught new masks
without an app release. So the collateral screen takes the plain
`image_picker` camera — no mask, the customer frames the shot — while **step 7
keeps the bridge**, where the ID-card and selfie masks are exactly right. A
test pins the split, because "tidy up the two capture paths" would quietly
undo it.

⚠ **That made a downscale mandatory**, and it is not optional decoration:
`image_picker_for_web` **ignores `maxWidth`/`imageQuality`** (it is a hidden
`<input type="file" accept="image/*" capture>`), so the browser hands back the
camera's full-resolution file and the ≈1280 px/JPEG-80 downscale the bridge
used to do no longer happens. Seven of those base64-encoded into one JSON body
is tens of megabytes. `services/image_downscale.dart` re-encodes each capture
through a canvas and `toDataURL('image/jpeg', q)` — the browser's own native
encoder, because `dart:ui` cannot encode JPEG at all (PNG and raw RGBA only,
and a PNG of a photograph is *larger*) and `package:image` takes seconds per
12-megapixel photo inside a WebView. It never throws: any failure returns the
original bytes, since an oversized photo beats a lost one.

Step 5 also now depends on the **host's file chooser** (`onShowFileChooser` and
its iOS equivalent) rather than the camera handler. That path is already
exercised by `p_loan/submit_form`'s attachment groups, so it is not new ground
— but it is the first thing to check if the button does nothing on a device.

#### `POST /GetRecalTopupData` — the settlement breakdown

**ยอดที่ต้องชำระเพื่อเติมวงเงิน on the redesigned amount screen comes from the
backend**, not from `/topup/detail` (added 2026-09-12; sample in the
git-ignored `etc/new_topup_api.txt`). It re-prices a chosen `topup_amount` and
returns a superset of `/topup/detail` plus the parts that call has no fields
for: `settlement_items[]`, `settlement_total_amount`,
`overdue_principal_amount`, `topup_discount_amount`,
`payoff_before_settlement_amount`, `overdue_day` / `overdueFrom` / `overdueTo`
(⚠ the last two are **camelCase** where everything around them is snake_case),
`campaign_code` and `campaign_fees`.

**The rows are the server's, and only they decide whether the section exists**
(instructed 2026-09-12). Each `settlement_items` entry carries its own Thai
`description`, rendered verbatim in `seq` order; the client maps nothing, names
nothing and totals nothing. **Empty `settlement_items` hides the whole
block** — heading, rows, total and the two buttons under it —
`TopupRecalculation.hasSettlement`.

That matters twice over. The design's six rows (ดอกเบี้ยสัญญาปัจจุบัน,
ดอกเบี้ยค้างชำระยกมา, ค่าติดตามทวงถาม, ค่าเบี้ยปรับ, เงินต้นค้างชำระ, ส่วนลด) do
not all exist as fields on `/topup/detail`, and guessing which of them `yield`
meant would have put a wrong figure on a bill; the sample returns **three**
items, not six, so the length is variable. And `settlement_total_amount` is
displayed **as sent** rather than summed from the rows — the customer is being
told what to pay, and a client that re-adds them can disagree with the server.
`itemsSumMatchesTotal` exists to leave a breadcrumb when they differ, never to
override the total. A test pins that a total with no rows still hides the
section: the rows decide, not the total.

⚠ **It is not callable from a browser, and that is why the client never
throws.** Verified 2026-09-12 against the sample host
`http://34.142.213.42:8080`:

| | |
| --- | --- |
| `POST` with the sample's `Basic` header | **200** with the full body — so the earlier 401s were auth, not the payload |
| any response | **no `access-control-allow-*` header** |
| `OPTIONS` preflight | **401** — a browser never sends `Authorization` on a preflight, so it can't get past it |
| the URL itself | plain **HTTP on an IP** — mixed content from this HTTPS build |

So it works only **inside the host**, through its `httpRequest` bridge, and
only once `http://34.142.213.42:8080/` is added to
`_kHttpRequestAllowedPrefixes` in the srisawad app — an app release, exactly
like the retired `<:8082>/SavePloanContract`. `POST /GetRecalTopupData` is
**not** on the mobile API base (it 404s there).

`TopupApi.recalculate` therefore returns **`TopupRecalculation?` and returns
`null` on every failure** instead of throwing. An unconfigured build, an
unreachable gateway and a contract with nothing outstanding then render the
*same* screen — the section is simply absent — which is what the rule above
already says. A top-up amount is perfectly requestable without a settlement
block, so a failure here must not take the page down with it. Every null leaves
a `Diagnostics.log` breadcrumb, readable from the `(UAT ver…)` tag, because
otherwise "why is the section missing?" is unanswerable from a device.

⚠ **The sample's credential does not ship.** It is a shared `Basic` service
account (a `…prod` user), and baking one into a web bundle is the
high-severity pentest finding this repo closed on 2026-08-04 by deleting
`kPLoanSaveApiAuth`. `kTopupRecalApiAuth` is a `--dart-define`
(`TOPUP_RECAL_API_AUTH`) defaulting to **empty**, pinned by
`test/topup_recalculation_test.dart`, and unset the call is skipped entirely.
Same rule, same shape as the lead fallback below. The real fix is for this call
to move behind the mobile API with the customer's own bearer token — see
Outstanding #33. The base URL follows the usual order:
`api_url['recal_topup_url_base']` from the Firestore config, then
`kTopupRecalApiBase` (`TOPUP_RECAL_API_BASE`) as the degrade-to value, so
moving the endpoint is a config edit rather than a rebuild.

#### The lead fallback (`TopupApi.saveLead`)

`POST {lead base}/ssw_service_api/api/leads/lh-save` — filed instead of a
top-up when `TopupFlow.outcome` is `lead`. Somebody calls the customer back.

⚠ **Its credentials are build-time inputs that default to empty, and that is
deliberate.** The source hardcoded both an `x-api-key` and a bearer into the
bundle. Shipping either would put a shared service credential back into a web
build anyone can read — the finding that deleting `kPLoanSaveApiAuth` closed on
2026-08-04. Unset, the branch reports itself unconfigured
("ระบบส่งข้อมูลยังไม่พร้อมใช้งาน กรุณาติดต่อสาขา") rather than calling the
endpoint unauthenticated. `test/topup_flow_test.dart` pins that nothing ships.

```sh
flutter build web ... --dart-define=TOPUP_LEAD_API_BASE=...                       --dart-define=TOPUP_LEAD_API_KEY=...                       --dart-define=TOPUP_LEAD_API_AUTH=...
```

The base is also readable from `api_url['lead_url_base']` in the Firestore
runtime config (config first, define as the degrade-to). **The real fix** is
for this call to move behind the mobile API and authenticate with the
customer's own bearer token, the way `POST /ploan` does — see Outstanding #28.

`TopupLeadSubmission` forwards the contract's own sub-objects
(`contract_details`, `car_details`, `payment_details`, `topup_detail`,
`barcode_details`, `insurances`) from `LoanContract.rawJson` rather than
re-serialising them from typed fields, which would silently drop any key this
model does not know about. `rawJson` exists for that and nothing else.
`pdpa_flg` goes out **empty**: a lead never reaches step 7, so claiming a
consent there would record one that was never given.

⚠ **The amount screen reloads when the QR screen pops** (fixed 2026-09-12).
Popping does not re-run `initState`, so without an explicit reload the screen
kept the `/topup/detail` it fetched *before* the payment — `interest_paid_flag`
still `'Y'` — and went on asking for money the customer had just paid. The push
to the QR screen is awaited and `_load()` follows it, so every way back (its
ปรับปรุงยอดชำระ, its back arrow, a system back) refreshes.

Re-reading `/topup/detail` is the **only** way this app learns a payment
landed: it never sees the bank transaction. That is also why the QR screen's
ปรับปรุงยอดชำระ refreshes nothing itself and simply pops — two screens
refreshing independently could disagree about whether the interest is still
owed.

#### `POST /payment/interest` — the 500 was the host, not the body

⚠ **Resolved 2026-09-11: `https://dev.swpfin.com:7076` had been retired.** The
call succeeds against `https://srisawad-qa.ecorpgroup.com`, which is what the
config already pointed at — so the failure was a *reproduction* against the old
host, not the app's payload. `AppEnvironment.uat.mobileApiBase` has been moved
to the working host so a config-read failure cannot land there either.

The three payload corrections below were made while chasing it. They are
**still right** — each matches the source exactly, and the decimal one was a
genuine defect with effects well beyond this endpoint — but none of them was
the 500. Keep them; don't credit them.

| Field | Wrong | Right |
| --- | --- | --- |
| `comcode` | `contract_details.comcode` | **`barcode_details.comcode`** — a different field, and the one that identifies the biller |
| `firstname` / `lastname` | the app user's profile name | split from the **contract holder's** name (`contract_name`) |
| `interest_amount`, `collection_fee`, `penalty_fee` | `int` | **`double`** — see below |

⚠ **`yield`, `collection_fee` and `penalty_fee` are decimals on the wire** and
were being parsed as `int` on both `LoanAmountDetail` and
`LoanContract.topupDetail`. That truncated `2987.84` to `2987` — misstating an
amount the server bills against an exact figure, *and* changing the JSON type
it is handed. It also made the QR total and the deduction rows wrong (the
manual's screenshot shows `9.15`, which an int renders as `9`). Now `double`
everywhere, with tests. Nothing in the P-Loan flow reads these three, so the
widening touched no P-Loan behaviour.

The name split is also made safe: the source does `name.split(' ')[1]`, which
throws `RangeError` on a single-word contract name and drops the third token of
a three-part one. `_splitContractName` takes the first token as the given name
and everything after it as the surname.

#### The interest-payment QR

**The layout is the source's, deliberately** (rebuilt 2026-09-12 against
`customer_topup/qr_payment_page/` and manual §2.3, replacing this app's usual
card idiom). A payment screen is one the customer may have seen in the other
app minutes earlier, and two different-looking QR pages for the same bill
invites doubt about which is real. So the plate/amount row, the 2pt divider,
the red payment-window note, the navy `คิวอาร์โค้ด` pill, the 250×250 QR block
with `drawText: true`, the R1/R2 lines and the two 140×60 buttons all sit and
read as they do there.

⚠ **This is the one page that carries its own colours** (`_QrPalette`), not
`LoanRegisterStyles`. They are the source theme's values and the difference is
visible — its caption grey is darker (`#646464` vs `#9AA0A6`), its navy deeper
(`#003063` vs `#1B3A6B`), its red pure (`#FF0000`). Matching the customer's
memory of the screen beat matching the rest of this app; that trade does **not**
generalise, so don't copy the pattern to another page.

⚠ **The second button is คัดลอกข้อมูล, not the source's บันทึกรูปภาพ.** That one
saves the QR through a native custom action this build has no equivalent for,
and a web download inside the WebView is not reliably honoured — it would be a
button that silently does nothing. Copying the payment payload always works and
a screenshot covers the rest. Swap it back only alongside a host handler that
actually saves.

The amount is read off `/topup/detail` rather than the contract's own
`topup_detail` (which is what the source uses): the detail call is re-read when
the customer returns from paying, so it is the one that goes stale last.


⚠ **`topup_qr_payment_page`'s barcode payload is byte-for-byte the source's
`genQRCodePayment`, trailing `.0` included.** It multiplies by 100 and calls
`toString()` on a `double`, so ฿1,234 renders as `123400.0` rather than the
integer satang the barcode standard describes. That looks wrong, but it is what
the shipped app prints and what the bank's scanner is known to accept, so it is
reproduced rather than "fixed" — changing a live payment reference on a hunch is
not a change to make from here. Confirm the intended format with the payments
team before touching it (Outstanding #29).

#### Payload (`models/topup_submission.dart`)

`POST /topup` — **37 keys**, transcribed from the source's `SaveNewTopupCall`
and pinned by `test/topup_submission_test.dart` (the produced key set must
equal the API's exactly). Wire quirks that are real: `topup_argeement_file`
(the misspelling is the API's) and `save_pdf`, which nests the same
`ContractPdfRequest` that `/pdf/loan` was called with — so the request that
made the documents and the request that files them cannot disagree.

`unresolvedFields` reports only what is *unexpectedly* blank: a photo slot this
loan type never asks for is blank by design, and `latitude`/`longitude`/
`transno` are in `acceptedBlank` (GPS is captured un-awaited on step 7, and the
server assigns the transaction number). A failed submit appends the blank ones
to the message, because "HTTP 400" against 37 fields is unactionable on a
device, and drops a `Diagnostics.log` crumb readable from the `(UAT ver…)` tag.

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
untracked): `fetchUserDetail(hash, token: …)` (`GET /user/detail?hash_thai_id=…`,
payload under `results` with its own `code`/`message` — non-200 code throws) and
`fetchAddressBook(hash, token: …)` (`GET /profile/address/{hash}`). **Both
require** the `Authorization: Bearer` token from the `?token=` launch param, and
`token` is a `required` argument on each — `fetchUserDetail` didn't take one at
all until 2026-08-14, which is the pentest-#2 gap described under **API
groups**. Base URL +
`x-srisawad` header are per-environment on `AppEnvironment`
(prod `https://mobile-api.swpfin.com` + `x-srisawad: x1`;
uat `https://dev.swpfin.com:7076` + `x-srisawad: x1` — the new uat gateway
requires the header on **every** `api_url_base` call, changed 2026-08-04; it was
empty before). ⚠ Those base URLs are the **compile-time fallbacks**; the config
document overrides them and uat's now points somewhere else entirely — see
**Runtime config from Firestore**. Errors throw `UserApiException`. Models: `models/customer_detail.dart` (profile) and
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
`listIdps()` (`POST /idp/list`), `listServiceAs()`
(`GET /services/{serviceId}/as`), `findAsForIdp()`,
`createVerifyRequest()` (**`POST /rp/verify-with-data`** since 2026-09-10, mode
2, `request_type` per **gateway** — see below; returns the gateway's
`transaction_ref`, see **Issue 2** under **NDID Common Message standard**),
`getVerifyStatus()`
(`GET /rp/verify/{referenceId}`, status `CREATED|PENDING|ACCEPTED|REJECTED|
TIMEOUT|CANCELLED`), `closeVerifyRequest()` (best-effort cancel). Errors throw
`NdidApiException` (parses the node's `{status, message}` error body).

**`/rp/verify-with-data` — the data request** (2026-09-10). The verification
now also asks one Authoritative Source for the customer's info. Body is the old
`/rp/verify` one plus two fields:

```jsonc
"data_request_list": [{ "service_id": "001.cust_info_001",
                        "as_id_list": ["<AS node id>"],
                        "min_as": 1, "request_params": "{}" }],
"callback_url": "https://ndid.srisawadpower.com/ndid/callback"
```

`callback_url` is the srisawad gateway's **own** callback, so the AS payload
lands on the backend. **Nothing client-side reads it back**: `NdidVerifyStatus`
is unchanged and the poll is parsed exactly as before.

⚠ **It follows the gateway** (fixed 2026-09-11). It was hardcoded to
`https://ndid.srisawadpower.com/ndid/callback` — the **prod** host — so a
**uat** request asked the prod gateway to receive its callback. Both gateways'
sample curls use their own host (uat's reads
`https://uat.ndid.srisawadpower.com/ndid/callback`), so the value is now the
resolved base plus `NdidApi.dataCallbackPath` and there is nothing left to keep
in step by hand. `api_url.ndid_callback_url` overrides it per environment for a
gateway that receives callbacks elsewhere.

**⚠ uat pins the AS; prod resolves it.** As of 2026-09-11 uat's gateway cannot
resolve an AS from the chosen IdP, so `ndid_as_id_uat` in the config document
holds `A18AC373-9CCB-47B3-A285-9ADBA29AFEFC` — the sample curl's value — and
`NdidApi._pinnedAs` uses it in place of `findAsForIdp`. The bare `ndid_as_id`
is **deliberately unset**, so prod keeps resolving.

It lives in the **config, not a define**, for the reason the next paragraph
gives: a node id compiled into the client works on the gateway it came from and
fails on every other one. In the config it is per-environment and removable
without a rebuild — delete the key and uat goes back to resolving. `kNdidAsId`
exists as the degrade-to and **ships empty**, pinned by a test.

A pinned AS with no resolvable marketing name still makes the data request, but
the Request Message **omits the AS clause** — `_pinnedAs` tries the gateway's
own list for a name and falls back to `ndid_as_name`/`_uat`; naming a source we
cannot confirm is worse than naming none. ⚠ That means a uat run may not show
the `ประสงค์ให้ส่งข้อมูลจาก …` clause the NDID reviewer's reference image has;
prod, which resolves, does.

**Which AS otherwise: the same institution as the chosen IdP.** `findAsForIdp`
resolves it rather than hardcoding one, and the reason is worth keeping:

- **A bank's IdP node id and its AS node id are different values.** Verified
  2026-09-10 on the prod gateway — the 13 IdPs and 14 AS nodes share **no** id.
  What they share is `(industry_code, company_code)` inside `node_name`, which
  matched all 13 exactly. That pair is the join; the node id is not, and neither
  is the display name.
- **The sample curl's `as_id_list` value is not on the prod gateway at all.**
  Baking `A18AC373-…` in would have been the hardcoded `'Authen Only'`
  `request_type` mistake of 2026-07-31 in a new costume — a gateway-specific id
  compiled into the client, failing only on the environment that matters.
- **It is what the customer consented to.** They picked that bank to
  authenticate with, and the Request Message names it as the data source, so
  asking a *different* bank would describe one relationship and exercise another.

⚠ `GET /services/{id}/as` does **not** flatten its entries the way `/idp/list`
does: the only identifying field is `node_name`, a JSON **string**. `NdidAs`
parses it; `decodeNodeName` never throws, so a malformed value costs the data
request, not the verification.

**A failed AS lookup degrades to `POST /rp/verify`**, with no
`data_request_list` and no AS clause in the message. The customer is there to
prove who they are and the AS payload is backend-only, so a gateway hiccup or an
unmatched IdP must not fail the identity step. Every such fall-back leaves a
`Diagnostics.log` breadcrumb (readable from the `(UAT ver…)` tag), because
otherwise "why did this go out without data?" is unanswerable from a device.

⚠ It costs **two extra gateway calls** per verification creation (`/idp/list` +
`/services/{id}/as`), which the 100-per-900 s rate limit absorbs easily — they
happen once, not per poll. See the rate-limit note below before adding more.

**The exact body is inspectable on the device** (added 2026-09-11).
`NdidVerifyRequest` carries `endpoint` and `sentBody` — the map as posted, not
a reconstruction, so the dialog cannot disagree with the wire — and
`ndid_verify_page` offers **ดู Request Body (debug)** which shows it with a
**คัดลอก** button. It appears after the create call whether it succeeded or
failed, because "what did we actually send?" is the first question either way.

The endpoint line is the more useful half: `/rp/verify` vs
`/rp/verify-with-data` says immediately whether an Authoritative Source was
resolved, which is the thing that degrades silently.

⚠ **Non-prod only**, like `EnvVersionTag`, the diagnostics sheet and the
`/ploan` failure report: `identifier` is the customer's citizen id. The dialog
says so on screen.

**Verified against the live gateway 2026-09-10**, body-shape only: posting the
generated body with citizen `0000000000000` reached `20005 - No IdP found`, i.e.
past structural validation, creating no real request. The response names the
proxied endpoint, `/identity/verify-and-request-data`. ⚠ **No real customer has
run this path yet** — see Outstanding #27.

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
node manages its own NDID token; client auth is an `X-API-Key` header — note a
web build can't keep it secret from clients anyway.

**⚠ The key is per gateway, and travels with `ndid_url_base`** (2026-09-10).
Each node accepts only its own, verified against `GET /request-types`: the prod
key is **401** on uat and the non-prod key is **401** on prod. That is a trap,
because the gateway comes from the Firestore config — editable with no rebuild —
while the key is compiled in, so editing that one field used to leave the key
behind and 401 every NDID call until someone shipped a matching build.

`ndidApiKeyFor(base)` (`config/app_environment.dart`) closes it by picking the
key off the **resolved host**, so `ndid_url_base` is sufficient on its own in
both directions and a rollback is a config edit rather than a release.
`NdidApi._request` resolves the base **once** and passes it to `_headers`, so a
key can't be paired with a different gateway than the URL it is sent to.
Matching is on `Uri.host`, so the SIT node's path (`dev.swpfin.com/dap`) and any
trailing slash both land correctly, and an unrecognised gateway gets the
**non-prod** key — prod's is the one that should never be guessed at.
`--dart-define=NDID_API_KEY=…` still pins one key for every gateway;
`kNdidApiKey` is now **empty by default**, which is what enables the pairing.
`test/ndid_api_key_test.dart` pins all of it, including that no override ships.

**⚠ The gateway rate-limits to 100 requests per 900 s, and the 3 s poll blows
it.** Found 2026-07-31 in the response headers (`ratelimit-policy: 100;w=900`,
`ratelimit-limit`/`-remaining`/`-reset`); the counter is **shared across
endpoints**, `/rp/verify/{ref}` included. The uat gateway is an Express app
behind an AWS ALB in `ap-southeast-7`.

`ndid_verify_page.dart` polls every 3 s = 20/min = **300 per window against a
limit of 100**. So it spends the budget in the first 5 minutes and is throttled
for the remaining 10 of every 15-minute window — roughly **40 of the 60 countdown
minutes blind**. A status flipped on the NDID console during a throttled stretch
cannot be seen until the window resets, which is the likeliest cause of the
"status is success but it keeps counting down" report (DNS was the other half).

**Fixed 2026-07-31.** `ndid_verify_page.dart` now schedules each poll with a
**single-shot timer that reschedules itself** (not `Timer.periodic`, so the
interval can change): `_pollFast` 3 s for the first `_fastPhase` 30 s — where
almost every real accept lands — then `_pollSteady` 15 s. That is ≈70 requests
per window including `/idp/list` ×2 and the create call, under the limit for a
full hour. An HTTP 429 sets `_pollAfter429` (60 s) for the next poll and says so
on screen.

The 429 delay is **fixed rather than read from `ratelimit-reset`**: the host's
`httpRequest` bridge returns only `{status, body}`, so response headers never
reach the app. Over-waiting is cheaper than being throttled again.

The slower steady rate costs little because detection no longer depends on the
timer: the resume-poll and ตรวจสอบสถานะ both check on demand. Note
`_scheduleNextPoll` measures elapsed time from the **countdown**, not a wall
clock, and the countdown-expiry branch gates on `_referenceId` rather than
`_pollTimer.isActive` — a single-shot timer is legitimately inactive between
polls, so the old check would have skipped the timeout message half the time.

**`POST /rp/verify` sends no `request_type`** (settled 2026-07-31). The field is
**optional on both gateways** — verified by posting without it to each, which got
past validation to `20005 - No IdP found` in both cases — and uat does not use
it, so it is omitted.

It got here the hard way: a hardcoded `'Authen Only'` that the SIT node accepts
and the uat gateway refuses with **`20091 - Invalid request type`**. Each
environment publishes its own set at **`GET /request-types`**
(`NdidApi.listRequestTypes()`, kept purely as the diagnostic for a 20091) and
the two sets are **disjoint** — both listed in
[docs/HISTORY.md](docs/HISTORY.md#ndid-request-type).

Because those don't overlap, the seam is **kept but opt-in** rather than deleted:
`ndid_request_type` (top level of the config document, *not* inside `api_url` — it
isn't a URL) → `kNdidRequestType` (`--dart-define=NDID_REQUEST_TYPE`), and
**empty — the default — omits the key entirely**. So SIT stays reachable by
setting one value, with no code change, and pointing `ndid_url_base` at a gateway
whose list differs can't silently send a wrong type.

⚠ If you ever do set one, get it from the DAP/NDID team. `request_type` names an
NDID service, so it can change the consent wording the IdP shows the customer and
how the request is billed — "the gateway accepted it" is not evidence it is the
right one.

**Base URL is config-driven** (since 2026-07-31), the same shape as
`SrisawadApi.baseUrl()`: `NdidApi.baseUrl()` resolves
`api_url['ndid_url_base']` from the Firestore runtime config →
`kNdidApiBase` (`--dart-define=NDID_API_BASE`, default
`https://dev.swpfin.com/dap`). Config first because the key is **per-project**,
so the uat document points at the uat node and prod's at prod without a rebuild;
the define stays as the degrade-to value when the document can't be read. It's
awaited per request — `_request` resolves it once and builds both the URL and
the `X-API-Key` from that one value. Point the define at
`http://localhost:7088` to hit a locally-run node — an `http:` URL additionally
needs the WebView to allow mixed content when the app is served over `https:`.

⚠ **The gateway URL and the host's allowlist are coupled across two repos, and
only one of them is editable without an app release.** The host proxies NDID
through `httpRequest` and refuses any URL outside its compiled-in
`_kHttpRequestAllowedPrefixes`. So a Firestore edit can point this build at a
gateway the app then rejects with `URL not allowed`. That is what happened on
2026-09-10; see **Outstanding** #22.

The uat document holds **`https://uat.ndid.srisawadpower.com`** again as of
2026-09-11 — the stopgap #22 itself describes, rolled back from the production
gateway it briefly pointed at on 2026-09-10. This one **is** allowlisted in the
shipped host, so in-app NDID works on uat without waiting for an app release.
Both are a *different node* from the DAP dev gateway the define defaults to: they return
**real banks** (ธนาคารเกียรตินาคินภัทร, เจ เวนเจอร์ส, …) with `logo_url`s, not the
DAP node's `idp1/idp2/idp4`. Because it has **real identities**, the
`kNdidTestThaiId` substitution was deleted on 2026-07-31 (see **NDID signing**) —
the flow now asks about the actual customer everywhere. Note the node also sends
`logo_url` + `has_logo`, which `NdidIdp`/`_toBank` ignore: bank tiles are still
drawn from the hardcoded `_knownBankStyles` colour list, and an IdP outside it
falls back to an orange tile with its id upper-cased.

### NDID Common Message standard (`services/ndid_common_message.dart`)

**NDID rejected the app review on 2026-08-28**; the reasons are in the
(git-ignored) `dap/NDID-Issues.txt`. Two of the three were code:

| # | NDID's finding | Fix |
| --- | --- | --- |
| 1 | The User Journey ppt shows the NDID T&C, the video does not | **No code change needed** — see below |
| 2 | The Transaction Ref is wrong; it must be **digits only, ≤ 9** | the gateway's `transaction_ref` + the standard Request Message |
| 3 | IdP & AS errors must use the standard Common Messages | `NdidCommonMessage.forErrorCode` |

Everything here is quoted from **005 แนวทางการพัฒนาบริการ NDID สำหรับสมาชิก**
Rev. 1.0 (11 Feb 2021) §6.2.1, pages 31–39 (`dap/005_*.pdf`). Extracting it is
fiddly and worth recording: `pdftotext` **drops Thai entirely** on this file, and
`pypdf` keeps it but splits `ำ` (U+0E33) into a space plus `า` — so text lifted
from it must be re-joined before comparison or it will never match.

**Issue 2 — the Transaction Ref is the RP's, not NDID's.**
Page 38: *"RP ทำการ generate เอง … ต้องมีความยาวขั้นต่ำ 5 ตัว แต่ไม่เกิน 9 ตัว
และเป็นเฉพาะตัวเลขเท่านั้น"*. The screen had been showing the first 12
characters of NDID's own `ndid_request_id`, upper-cased (`8CB4B22F15A4`) — hex,
and 12 long, so it failed both halves of the rule. NDID's `reference_id` is a
UUID and cannot be reshaped into a legal value, so a **separate** reference is
needed.

⚠ **Nothing in the DAP proxy spec supplies one.** Searched all 236 pages of
`dap/NDID_Proxy_Specification_V4.0.pdf` on 2026-08-31: the string
"Transaction Ref" does not appear. `POST /ndidproxy/api/v2/identity/verify`
(p.43–47) takes no client reference field, and the two ids it returns are both
illegal as one — `reference_id` (a UUID, *"the identifier for using to access the
status later"*, p.47) and `ndid_request_id` (64 hex chars). Its only carrier is
the free-text `request_message`, which the spec describes as *"Message or content
which are sent to IdPs to inform the users about the detail for identity
request"*. So the reference is generated on the RP side, by design, and travels
inside that string.

**The srisawad gateway generates it — this app does not** (changed 2026-08-31 on
instruction). Between 2026-08-28 and 2026-08-31 `NdidTransactionRef.generate()`
minted one per request and `NdidApi.createVerifyRequest` **required** it, building
the standard Request Message around it. The backend then added a
**`transaction_ref`** field: the gateway generates the reference, appends the
`(Transaction Ref: …)` clause to the message it forwards to the IdP, and returns
the value on **`POST /rp/verify`** *and* on every **`GET /rp/verify/{ref}`**.

So now:

- `NdidApi.createVerifyRequest`'s `transactionRef` is **optional and normally
  omitted**, and `NdidCommonMessage.requestMessage()` renders **no
  `(Transaction Ref: …)` clause** when it is null. Passing one would put a
  *second, different* reference in front of the customer — the review failure
  wearing the opposite mistake. It stays supported for a gateway that composes no
  clause of its own (the DAP/SIT node).
- `NdidVerifyRequest.transactionRef` / `NdidVerifyStatus.transactionRef` carry the
  gateway's value (`readTransactionRef` in `ndid_api.dart`, tolerant of a
  camelCase spelling and of an empty string). The 60-minute countdown screen
  displays it.
- **The poll is the backstop, not a second source.** `ndid_verify_page` adopts
  `transaction_ref` from the create response, and from a poll **only when it has
  none** — re-reading it on all ~70 polls of an hour would log a "missing"
  breadcrumb per poll on a gateway that never sends the field.
- **No local fallback, deliberately.** With no `transaction_ref` the screen shows
  `-` and `Diagnostics.log` records it. Filling that with
  `NdidTransactionRef.generate()` would show the customer a number their bank
  never displayed, since the IdP is quoting the gateway's clause. `generate()`
  survives as the RP-side fallback for the SIT node and is called by nothing in
  the live flow; **`isValid` is the load-bearing member now** — it checks the
  *gateway's* value against p.38's rule and leaves a breadcrumb when it fails,
  which is what turns "the reference looks wrong" into something the backend team
  can act on.

The same number must appear in two places, which is the other half of the
finding: on our waiting screen **and** inside the `request_message` the IdP app
shows. One generator is what guarantees that, and it is now the backend's.

✅ **Verified end to end 2026-09-10 — issue 2 is closed.** A live run showed
`312461174` on our countdown screen, and the KBank consent screen quoted the
**same** reference inside the forwarded message, complete with the AS clause.
So the gateway generates it, appends the clause, and returns the value; one
generator, one number, both places. Evidence and the exact rendered text are in
Outstanding #26. ⚠ Note the gateway writes `(Transaction Ref:N)` with **no
space** after the colon, matching p.38; `requestMessage` was corrected to
match.

**The Request Message carries the standard's AS clause again** (2026-09-10).
The template is
*"…ของ [RP] และประสงค์ให้ส่งข้อมูลจาก [AS 1, AS 2, …] (Transaction Ref:…)"*, and
now that `createVerifyRequest` posts `/rp/verify-with-data` with a
`data_request_list`, there **is** an Authoritative Source to name — the one bank
the customer picked as their IdP. `NdidCommonMessage.requestMessage` takes
`asNames` and renders the clause before the Transaction Ref.

It is still **conditional**, because the no-data path is real: when no AS matches
the chosen IdP the request degrades to plain `POST /rp/verify`, and naming a bank
there would tell the customer their data is being fetched when it is not. §6.2.1
bullet 2 permits adjusting wording for clarity, and describing exactly the
parties in the request is the honest reading either way.

⚠ Between 2026-08-28 and 2026-09-10 the clause was dropped unconditionally, and
**the reviewer's reference image shows an AS** — so the with-data path is what
the submitted user journey describes. Confirm against that document (#25).

**Issue 3 — the error messages are the standard's, not ours.** The verify page
used four sentences of its own (`'การยืนยันตัวตนถูกปฏิเสธจากธนาคาร'`, …). Now
`NdidCommonMessage.forErrorCode` maps all 18 documented codes — IdP `30000`–
`30900`, AS `40000`–`40500` — to their published wording, and an unknown code
falls back to the standard's own catch-all rather than showing a raw number.

That needed a wire change too: `NdidVerifyStatus` **read `status` and nothing
else**, so the IdP's `error_code` — which arrives inside `response_list` — was
being discarded and every distinct failure showed one generic sentence. It also
never handled the gateway's two error statuses (`REQUESTED_ERROR`,
`IDP_OR_AS_ERROR`), which fell into `isPending` and polled a dead request for the
full hour.

**Verified verbatim against the PDF on 2026-09-01.** All 18 error messages,
plus [2], [3] and the p.39 catch-all, appear character-for-character in the
document's own extracted text (whitespace normalised, `ำ` mapped to `า` — see the
extraction note above). Exactly **two** strings deviate, both declared in the
source:

| Row | Deviation | Why |
| --- | --- | --- |
| [5] | doc writes `กรุณาเลือก IdP รายอื่น`; we write `ผู้ให้บริการยืนยันตัวตนรายอื่น` | bullet 4 forbids showing the literal word "IdP", and every other row spells it out — the document contradicts itself in this one row |
| [28] | the `และประสงค์ให้ส่งข้อมูลจาก [AS 1, AS 2, …]` clause is dropped | mode 2 requests no AS data; naming a bank would claim a fetch that does not happen |

⚠ **No test enforces the wording**, and the header comment in
`ndid_common_message.dart` used to claim one did — corrected 2026-09-01. The test
pins *structure* (every code distinct, no `[IdP]`/`XXX` leak, unknown → catch-all);
it cannot read the PDF, because `dap/` is git-ignored and CI would fail on the
missing file. Re-run the comparison by hand after editing any string.

**A bare `REJECTED` shows the catch-all, not row [6].** `forStatus` special-cases
only `CANCELLED`; `REJECTED` and `TIMEOUT` fall through to `generalFailure`. In
practice a rejection carries an `error_code` and gets that code's row, so this
only bites when the gateway sends none. The standard *does* have dedicated
wording at [6] — left out because the PDF marks it
`***ขอยกเลิกกรณีนี้เมื่อ IdP ปรับเป็น API V.5 แล้ว***` — so if a reviewer looks
for it, that is where it went. Adding it is two lines in `forStatus` plus a test.

**Five of the 13 IdP codes cannot be produced from a handset** (`30000`, `30200`,
`30400`, `30700`, `30900`) — they need NDID or the bank to inject them. So
finding 3 cannot be fully evidenced by device testing alone; ask for injection
support when booking the retest.

⚠ **The five AS codes are reachable now** (changed 2026-09-10). They were
impossible while every request went out with no `data_request_list`;
`/rp/verify-with-data` puts an Authoritative Source in the request, so
`40000`–`40500` can actually arrive and `forErrorCode` will render them. They
are no longer evidenced by unit test alone — but they have **not** been seen on
a live request either, so treat the mapping as untested against the wire.

Two supporting details:

- **`NdidSubject.ndidIdpName`** was added because §6.2.1 bullet 4 requires
  showing the **IdP Marketing Name**, never the word "IdP" or a node id. One
  message (30900) names it; the bank-select page records it beside `ndidIdpId`.
- **`NdidCommonMessage.rpContact` is empty by default.** Four AS messages end
  "ติดต่อ RP Contact XXX". Rather than invent a phone number, an unset value
  degrades to "ติดต่อผู้ให้บริการ". Set the real one with
  `--dart-define=NDID_RP_CONTACT=…` — see Outstanding #24.

**Issue 1 needs no code.** `ndid_terms_page` (built earlier the same day) already
carries the NDID minimum-required T&C: all **12** clause paragraphs match
`dap/010_NDID-minimum-required-TandC/…/Schedule 5 Minimum required tem Thai
[26052020]_RP.docx` **verbatim**, once that template's own
`[กรุณาระบุชื่อบริษัทของสมาชิก]` placeholder is filled with the company name as
it instructs. Only the page heading is ours. The finding was that the **video**
did not show the screen — so the action is to re-record it, not to change code.
`dap/` is git-ignored, so this cannot be a test; re-check it by diffing the docx
text against `ndid_terms_content.dart`.

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
- **`httpMultipart` handler — still not needed (2026-08-04, re-confirmed
  2026-08-07).** It was only ever for the old `<:8082>/SavePloanContract`
  (multipart, **no CORS**). `POST /ploan` is multipart again since 2026-08-07,
  but it lives on the mobile API base, which sends
  `access-control-allow-origin: *` — so the upload goes direct through
  `package:http` (`bypassHostBridge: true`) and no handler is required. Note
  what the handler was actually for: **CORS, not multipart.** The snippet stays
  in `native_bridge.dart` as the reference pattern for a future upload to a host
  that doesn't send those headers.
- **`openBranchPicker` handler:** `pickBranch()` asks the host to open its
  branch-picker map (step-5 appointment). The host pushes a selection-mode map
  page and returns the chosen branch as a **JSON string** (`branchName`,
  `address`, `phone`, `lat`, `lng`); `null`/`''` = cancelled. Handler snippet
  also in `native_bridge.dart`'s doc comment.

### On-device diagnostics (`services/diagnostics.dart`)

Added **2026-08-17** to answer a class of bug report this build had no way to
investigate: *"the WebView went white."* Two very different things produce that
screenshot, and nothing distinguished them:

| What happened | What the tester sees |
| --- | --- |
| a Dart exception during `build` | `RenderErrorBox` — a **textless light-grey rectangle** in a release build |
| the WKWebView **content process was killed** | a blank white page; no Flutter code runs at all |

Neither was observable from outside. `isInspectable` defaults to false on
iOS 16.4+ so Safari Web Inspector cannot attach, the host's `onConsoleMessage`
output goes to an Xcode console the tester does not have, and the report arrives
as a photo of a white rectangle. **So the screen itself has to carry the
evidence.**

- **`Diagnostics.installHandlers()` runs first in `main()`**, before anything
  that can throw. It replaces `ErrorWidget.builder` with `DiagnosticsErrorView`
  — which names the exception and lists the breadcrumbs — and hooks
  `FlutterError.onError` plus `PlatformDispatcher.instance.onError` (uncaught
  *async* errors, which never reach the former). After that the two rows above
  tell themselves apart **from one screenshot**: text on screen means Dart threw,
  a blank white page means the process died.
- **Breadcrumbs survive a reload.** `DiagnosticsRouteObserver` records every
  push/pop/replace, an `AppLifecycleListener` records visibility changes, and a
  40-entry ring buffer is written to `SharedPreferences` on each crumb.
  `restorePrevious()` — called from `main()` after `initializePersistedState` —
  shifts the window and starts a fresh trail, so a boot can read **run N-1 and
  N-2**. Two slots rather than one because the failure destroys the JS context
  and the page returns through a full initial load, which is itself a run: with a
  single slot the evidence would be overwritten by the very reload that follows
  the crash.
- **A trail that ends with no `ERROR` crumb is the finding**, not the absence of
  one — nothing threw, so the run was *cut off*. Add `lifecycle hidden` before it
  and the view was backgrounded; without it, it died in the foreground.
- **Testers reach it by tapping the `(UAT ver…)` tag** in any AppBar
  (`showDiagnosticsSheet`): this run's trail plus the two before it, with คัดลอก
  and ล้าง. Hidden on prod, tag and sheet alike.
- ⚠ **`Diagnostics.report()` is a distribution channel** — it exists to be pasted
  into a chat. `token` and `hashThaiId` are **masked** in its URL line
  (`<redacted:N chars>`, keeping the length so "no token" and "token present"
  stay distinguishable). A tester sent an unmasked one before that was added.
  Keep them masked when adding fields.
- `DiagnosticsErrorView` uses `Container`/`Text`/`Directionality` and **no
  `Scaffold`, `Theme` or `MediaQuery`**, on purpose: `ErrorWidget.builder` can
  fire for a widget above `MaterialApp`, where there is nothing to inherit from,
  and anything fancier would throw inside the error path and put the blank
  rectangle back.
- `app_router.dart` gained an `errorBuilder` too, so an unmatched location renders
  the same screen instead of go_router's own.

#### What it found: the iOS white screen (root cause, 2026-08-17)

**The NDID bank-select page was crashing the WKWebView content process** — in the
foreground, on iOS only, entered from the LandAndHouseWeb top-up card.

Each logo tile is an `Image.network` with `WebHtmlElementStrategy.prefer`, i.e. an
HTML **`<img>` platform view**, which it has to be (the gateway sends no CORS
headers and its placeholder is an SVG — see the bank-select notes above). In
Flutter web's CanvasKit renderer **every platform view splits the scene into its
own GPU-backed overlay canvas**, on the order of 12 MB each at phone DPR. The uat
gateway returns **16** IdPs for a real customer — 1 registered, 15 not — and both
grids are built eagerly in a `Wrap` with no viewport culling, so all 16 appeared
at once. That is past what one content process gets, and worse with the
LandAndHouseWeb WebView still resident underneath.

Proven from a tester's breadcrumb trail (no `ERROR` crumb, no `lifecycle hidden`
before it). It only reproduced when the customer lingered, which is why it
looked intermittent — see [docs/HISTORY.md](docs/HISTORY.md#ios-white-screen)
for the trail and for the five hypotheses ruled out along the way, **recorded so
they are not re-litigated**.

**Fixed web-side by rationing logos:** `_kMaxLogoTiles = 4`, granted to the
**registered** grid only; every other tile falls back to `_codeMark` initials.
Registered is the right grid to spend the budget on — it is the bank the customer
actually uses, and it is normally one or two tiles. Shipped as uat **webVersion
74**.


⚠ One of those ruled-out rows carries a warning of its own — the host's
stale-version force-reload. If `sawad_loan_universal_version_uat` is ever set
*above* the live `WEB_VERSION` it forces a cold multi-MB reload on every open,
and its
`clearAllCache` is static/global — so it would wipe the sibling LandAndHouseWeb
WebView's cache too.

⚠ **The deciding test is still outstanding**: an iOS tester deliberately lingering
**30–60 s** on `/ndidBankSelectPage` before picking a bank. Android was retested
and is fine, but Android never failed, so that is "no regression", not
confirmation.

If the logos are wanted back in the not-registered grid, the two options
considered were: render one only for the **selected** tile (one extra platform
view, cheap), or **proxy the logos through our own origin** so `Image.network`
uses its normal byte path and needs no platform view at all (correct, needs
infra).

Still unshipped in the **host** (`_pentest_resolved`, uncommitted working tree —
needs an iOS build): `onWebContentProcessDidTerminate` → reload with a recovery
banner, `isInspectable` on non-prod, and the edge-swipe fix. None of the three
caused this bug; the first two are a safety net plus observability, the third is
a genuine defect.

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
client), `http_parser` (`MediaType` — so a multipart part can declare
`image/jpeg` vs `application/pdf` on the P-Loan save upload; already transitive
via `http`, named because we import it), `image_picker` (camera/gallery picking for the P-Loan attachment
groups; on web it's a hidden `<input type="file" accept="image/*">`, so it needs
the WebView host to support the file chooser), **`pdfx` 2.9.2** (renders the step-6
contract PDFs; pinned to the version the LandAndHouseWeb top-up flow uses, and
**needs the pdf.js script tags in `web/index.html`** — see **Step 6 documents**.
It also pulls native plugins for Android/iOS/desktop, harmless in a web-only
build, but do not open a document under `flutter test` — pdf.js isn't there),
**`barcode_widget`** (the Thai bill-payment QR on the top-up flow's
interest-payment screen; pure Dart, the same package the source uses there).
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
anyone who opens the app: the Firebase web API key (fine — it grants nothing) and
the **two** NDID gateway keys — `_kNdidApiKeyProd` and `_kNdidApiKeyNonProd`,
picked per gateway by `ndidApiKeyFor` (2026-09-10; it was a single
`kNdidApiKey` default before). Two rather than one because each gateway rejects
the other's key, so the bundle has to carry whichever one the Firestore config
may point at — the alternative was an app-release-coupled key, not a smaller
attack surface. The shared Basic service account `kPLoanSaveApiAuth` **used to be
here too** — it was **deleted 2026-08-04** when the P-Loan save endpoint moved to
`POST /ploan`, which authenticates with the customer's own Firebase bearer token
(see **P-Loan save API**). So the only baked-in secrets still worth rotating are
the two NDID keys (a web build can't keep either from clients anyway).

~~**One identity check is deliberately weakened off prod.**~~ **Closed
2026-07-31.** `kNdidTestThaiId` made non-prod builds run NDID against
`1234567890123` rather than the applicant, because the DAP uat node had no other
registered identity. The uat gateway now has real ones, so the define and its
`ndidThaiIdOverride` gate are **deleted** and no environment substitutes an
identity — `PLoanFlow.ndidThaiId` is the customer's own id, pinned by a test. No
build flag can bring the substitution back.

**The top-up flow ships no credential either.** Its lead fallback needs an
`x-api-key` and a bearer that the FlutterFlow source hardcoded; here both are
`--dart-define` inputs that default to **empty**, and an unconfigured build
reports the branch unavailable rather than calling the endpoint
unauthenticated. A test pins that nothing ships. See **The lead fallback**.

**The top-up flow's ID check is not weakened either.** The source accepted four
hardcoded Thai IDs alongside the customer's own — the same backdoor the P-Loan
port refused — and it is not reproduced. A test pins all four shut.

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
2. ~~Implement the `httpMultipart` bridge handler in the host app.~~
   **Resolved 2026-08-04, still resolved 2026-08-07.** `/ploan` is on the
   mobile API base, bearer-authenticated and CORS-enabled, so the multipart
   upload goes direct (`bypassHostBridge: true`) — no handler, no `:8082`
   allowlist entry. **Both submit blockers are gone for the Extra path.**
   [History](docs/HISTORY.md#outstanding-2-3).
3. ~~Do something about `kPLoanSaveApiAuth`.~~ **Resolved 2026-08-04.** The
   Basic service credential was **deleted** with the move to bearer auth on
   `/ploan`. The two NDID gateway keys are the only baked-in secrets left — a
   web build can't hide them regardless.
4. **Bump `sawad_loan_universal_version_uat` in the *srisawad host's* appConfig**
   to match the deployed `WEB_VERSION` (**74** as of 2026-08-31), or the host's
   stale-cache auto-reload never fires. Note the number now moves on most
   sessions, since the `Stop` hook deploys uat on any turn that changes source —
   check what is actually live rather than trusting this figure.
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
   **Resolved 2026-07-30.** `PLoanFlow.payoutAmount` is `requested − duty` for
   **both** kinds; `LoanAmountDetail.payoutFor` was **deleted** rather than
   deprecated so the old top-up formula can't be picked up by name.
   [History](docs/HISTORY.md#outstanding-8-9).
9. ~~LandAndHouseWeb's button is not built yet.~~ **Built** — `openPLoanExtra`
   is wired to `productCode == 'PLD001'` (see **What LandAndHouseWeb has to
   do**). What remains is the user pasting the **browser-capable variant** into
   FlutterFlow if they want it to work when testing on the web.
10. **The host-app edits need an app release.** `routegenerator.dart` and
    `video_record_web_widget.dart` are committed on `main` in the srisawad repo;
    `loan_card.dart`'s PLD001 chip was added 2026-07-30. Only a new
    Android/iOS build puts the `srisawad://ploan-extra` interception on a
    tester's phone — deploying this web repo can't.

**Open in this repo, deliberately not done:**

11. ~~**🐞 `POST /topup` hardcodes both PDPA consents to `'Y'`.**~~ **No longer
    reaches a customer** since the 2026-07-31 retarget — `toSubmissionJson()`
    is off every submit path. The literal `'Y'`s are still in the code at
    `p_loan_flow.dart:791-792`, left as-is deliberately: that method is the
    record of the dead `/topup` wire format. If `/topup` is ever revived, fix
    it *then* — or delete the method and this note together.
12. ~~**No live P-Loan save submit has ever run.**~~ **Resolved 2026-08-17** — a
    live `POST /ploan` succeeded against a real contract (`SLOAN`), settling
    multipart, the CORS preflight and body size in one shot
    ([details](docs/HISTORY.md#outstanding-11-12)). ⚠ Two caveats survive: it
    was **one** submit from one entry point, so a timeout or request-size limit
    is still the first suspect if a working submit starts failing; and the two
    photos were merged into `cardIdImage[]` on **2026-09-02**, *after* it, so
    that half of the part shape is once again **unproven on the wire**.
13. **The top-up-card chain has been walked, but never submitted *from there*.**
    On 2026-07-30 the user ran the real chain — srisawad app → LandAndHouseWeb
    top-up card → this build — as far as **step 4**, where the PDF viewer turned
    out to be blank on Android (fixed, #18). So the deep link, the host
    interception and steps 3 → 5 → 6's data are all confirmed against a live
    contract (`MLOAN` / `ฮฮM680702003NF61X`).

    **Update 2026-08-17:** a live `POST /ploan` submit has now succeeded (#12),
    so "nothing has ever been filed" is no longer true. What is **not** recorded
    is which entry point that submit came from — confirm it was the top-up-card
    path before closing this, since that path is the one that skips steps 2 and 4
    (#15).
14. ~~**`latitude` / `longitude` have no source.**~~ **Resolved 2026-08-07** —
    device GPS via `services/device_location.dart`, captured on step 6; no host
    change was required (see **P-Loan save API**). They still fall back to
    empty on a denial or no fix, deliberately.
    [History](docs/HISTORY.md#outstanding-14).

    **`gpsProvinceId`/`gpsAumphurId` are still open** — coordinates did not
    resolve them: they are srisawad's own province/district **ids**, needing a
    reverse lookup from lat/lng into an id set this app has no endpoint for.
    Left blank and reported.
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
    handler is **no longer wanted** — it would cost an app release to reach a
    worse UX. What remains is smaller: **self-host pdf.js**
    (`web/index.html` pulls 4.6.82 from jsDelivr, so a CDN outage blanks the
    contract viewer again). [History](docs/HISTORY.md#outstanding-18).
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
22. **🟡 Unblocked on uat by the stopgap; prod still needs an app release.**
    The uat config points NDID back at **`https://uat.ndid.srisawadpower.com`**
    as of 2026-09-11 — the rollback described at the end of this item. That
    host **is** allowlisted in the shipped app, so in-app NDID works on uat
    today. What remains blocked is pointing uat (or prod) at
    **`https://ndid.srisawadpower.com`**, the production gateway: the host must
    allowlist it, that entry is committed but unreleased, and the gateway sends
    no `access-control-allow-*` headers (re-verified 2026-09-10) so the bridge
    is mandatory and a plain browser cannot substitute — outside the host the
    bank-select page loads its **mock** grid, not the real API.

    `_kHttpRequestAllowedPrefixes` in the srisawad host's
    `loan_universal_web_widget.dart` now carries
    `https://ndid.srisawadpower.com/` **and** the uat host **and** the two
    Google API hosts, all **committed** — the prod one as `78076c5` on
    2026-09-10. ⚠ That commit is on branch **`pentest_resolved`**, not `main`
    (this note said `main` until 2026-09-10; the branch had moved). Only a new
    Android/iOS build carries any of them (same constraint as #10).

    ⚠ Prefix matching is `url.startsWith`, and
    `https://ndid.srisawadpower.com/` is **not** a prefix of
    `https://uat.ndid.srisawadpower.com/` — the uat entry never covered prod.
    A shipped app without the new entry fails every NDID call with
    `{"status":0,"error":"URL not allowed: …"}` — which is what the
    2026-09-11 rollback to the uat host avoids.

    The gateway is reachable and the key is right — `GET /request-types` on the
    prod host returns `200` with the four `dsign.*`/`easyconnext`/`idpconnext`
    types (2026-09-10). What is missing is only the host build. The stopgap —
    point `ndid_url_base` back at `https://uat.ndid.srisawadpower.com`, which
    **is** allowlisted in the shipped app, the key following automatically
    (see **NDID API client**) — **was applied on 2026-09-11**. Moving to the
    prod gateway again is a one-field Firestore edit, but only *after* the host
    build ships.

23. **A declined NDID agreement is logged only in the session.** ปฏิเสธ on
    `ndid_terms_page` calls `Diagnostics.log`, which is an in-memory breadcrumb
    trail readable from the `(UAT ver…)` tag and gone when the WebView closes.
    The design note says "กรณีปฏิเสธมีเก็บ log", which most likely means a
    server-side record of who declined and when — there is no endpoint for that,
    so nothing is posted. If a durable consent log is wanted, that endpoint is
    what is missing; the call site is the one `Diagnostics.log` in `_decline`.

24. **Set `NDID_RP_CONTACT`.** Four AS-error Common Messages tell the customer
    to contact us ("ติดต่อ RP Contact XXX" in the standard). No real contact is
    configured, so they currently say "ติดต่อผู้ให้บริการ" — correct, but less
    useful than a number. Build with
    `--dart-define=NDID_RP_CONTACT=<call centre>` once it is confirmed. A wrong
    number in front of a customer is worse than none, which is why it was not
    guessed. ⚠ This is the **one loose end inside finding 3's own scope** — the
    18 messages are otherwise verbatim (verified 2026-09-01).
24b. **Decide whether a bare `REJECTED` should use row [6].** Today it shows the
    p.39 catch-all; the standard has dedicated wording that the PDF also marks
    for retirement at IdP API V5. Two lines in `NdidCommonMessage.forStatus`
    plus a test. See **NDID Common Message standard** → *Issue 3*.
24c. **Ask NDID for error-code injection on the uat node.** Five IdP codes
    (`30000`, `30200`, `30400`, `30700`, `30900`) cannot be produced from a
    handset, so finding 3 cannot be fully evidenced by device testing without
    NDID's help. ⚠ The five AS codes **became reachable on 2026-09-10** with
    `/rp/verify-with-data` — they are no longer unit-test-only, but no live
    request has produced one, so ask for those to be injectable too. Device runbook:
    the **NDID Common Message Runbook** artifact (2026-09-01) —
    https://claude.ai/code/artifact/bbafc7f1-640b-4853-9604-0596fd4a51f0
25. **Re-record the NDID review video, and re-check the Request Message against
    the user-journey document.** NDID's issue 1 was that the video never showed
    the T&C screen — that screen exists now, so this is a recording task. While
    re-recording, note the reviewer's reference image shows the Request Message
    naming an **AS** (ธนาคารกสิกรไทย); this build names none, because it sends no
    `data_request_list`. If the submitted user journey promises AS data, either
    the journey or the request has to change — see **NDID Common Message
    standard**. ⚠ Do the run in #26 first — the Transaction Ref the video must
    show is the gateway's now, and nobody has yet seen one arrive.

    **Update 2026-09-10:** the AS half of this is resolved in code — the switch
    to `/rp/verify-with-data` puts an Authoritative Source in the request and
    the Request Message names it, so the build now matches the reviewer's
    reference image instead of contradicting it. What remains is confirming the
    **specific** bank: the reference shows ธนาคารกสิกรไทย, while this build names
    whichever bank the customer picked as their IdP. If the submitted journey
    promises one fixed AS, say so and it becomes a config value.
26. ~~**`transaction_ref` has never been seen on a live request.**~~
    **✅ Closed 2026-09-10.** Shipped 2026-08-31 (uat `WEB_VERSION` 74);
    verified end to end on uat `WEB_VERSION` 82, our screen and the bank's
    quoting the same reference.

    - ✅ **The field arrives.** A real run showed a genuine `transaction_ref` on
      the countdown screen, not `-`. So the gateway does generate and return it,
      and the half of NDID's issue 2 that is ours to display is **done**. (Had
      it been absent the breadcrumb trail — tap the `(UAT ver…)` tag — would read
      `ndid transaction_ref absent from gateway response`; a value breaking
      p.38's format logs `… is not 5-9 digits` and is still displayed, being
      what the IdP quotes.)
    - ✅ **The IdP app shows the clause, with the same number.** Confirmed
      2026-09-10 from a KBank consent screen photographed beside our own
      waiting screen: both quoted **`312461174`**. So the backend really does
      append the clause to the message it forwards, and NDID's issue 2 is
      **closed on both sides** — which was the one thing that could have failed
      the review again while our screen looked perfectly correct.

      What the bank rendered, in full:

      > ท่านกำลังยืนยันตัวตนเพื่อใช้ตามวัตถุประสงค์ของบริษัท ศรีสวัสดิ์ พาวเวอร์
      > 2014 จำกัด และประสงค์ให้ส่งข้อมูลจาก ธนาคารกสิกรไทย
      > (Transaction Ref:312461174)

      Four things fall out of that one screenshot: the RP name is ours, the AS
      clause is present and names the chosen bank (so #27's open bullet closes
      too), the reference is 9 digits of digits only — legal under p.38, at the
      maximum length — and the timings line up (KBank stamped 13:30 and asked
      for confirmation by 14:30, i.e. the `request_timeout` of 3600 s).

    ⚠ **The gateway writes `(Transaction Ref:N)` with no space after the
    colon**, which is how p.38's own template writes it. `requestMessage` had a
    space; corrected 2026-09-10. That branch only runs for a gateway composing
    no clause of its own (SIT/DAP), but the two paths should be
    indistinguishable to a customer.

    If the clause ever turns out to be ours to add after all, the revert is
    small and named: pass `transactionRef` to `NdidApi.createVerifyRequest`
    again (`NdidTransactionRef.generate()` is still there for exactly this) and
    prefer the local value over the response's on screen.

27. **🟢 `/rp/verify-with-data` is verified end to end.** Shipped and exercised
    2026-09-10 on the uat gateway. Only the AS **error codes** remain unseen.

    - ✅ **The data reaches the backend.** A live run delivered the AS payload to
      `callback_url`, confirmed by the user. So the AS responds, the gateway
      forwards, and the callback fires — the whole point of the endpoint. Note
      **nothing client-side can observe this**: `NdidVerifyStatus` is unchanged
      and reads no data, by design, so this can only ever be confirmed from the
      backend side.
    - ✅ **A real IdP → AS pair resolves.** Matching on
      `(industry_code, company_code)` held on a real run, as the live reads
      predicted: **13 of 13** on prod, **16 of 16** on uat. If a customer ever
      picks a bank whose AS is absent, the flow silently degrades to
      `/rp/verify` and the breadcrumb `ndid no AS matches IdP …` under the
      `(UAT ver…)` tag is what says so.
    - ✅ **The body shape** — the generated body reached `20005 - No IdP found`
      on prod, past structural validation; both endpoints also verified present
      on uat (`/services/{id}/as` 200, `/rp/verify-with-data` 400-on-empty).
    - ✅ **The IdP app shows the AS clause.** The KBank consent screen in #26
      read *"และประสงค์ให้ส่งข้อมูลจาก ธนาคารกสิกรไทย"* — the AS named is the
      bank the customer picked as their IdP, which is exactly what
      `findAsForIdp` resolves. So the clause, the resolution and the consent the
      customer actually sees all agree.
    - ⏳ ⚠ **The AS error codes** `40000`–`40500`, newly reachable and still
      never seen (#24c).

    ⚠ Confirmed against the **uat** gateway. Prod is still blocked behind the
    same app release as #22 — the shipped app does not allowlist
    `ndid.srisawadpower.com`, so in-app NDID cannot reach it. The uat gateway is
    allowlisted, which is why testing could proceed at all.

**Top-up flow (added 2026-09-11):**

28. **The lead fallback needs a home.** `POST /ssw_service_api/api/leads/lh-save`
    is on a different host and wants its own `x-api-key` + bearer, which the
    FlutterFlow source hardcoded into the bundle. Here both default to empty
    (`TOPUP_LEAD_API_KEY` / `TOPUP_LEAD_API_AUTH`) and the branch reports itself
    unconfigured rather than shipping a shared credential — so **the lead path
    does not work until someone either supplies the defines or, better, moves
    the call behind the mobile API** with the customer's own bearer token the
    way `POST /ploan` does. The second is the right fix; the first is a
    stopgap that puts the credential back in a readable bundle.
29. **Confirm the QR payload format with the payments team.** The interest
    barcode is reproduced byte-for-byte from the source, including an amount
    rendered as `123400.0` (a `double.toString()`) where the Thai bill-payment
    standard describes integer satang. It was not "fixed" because the source is
    live and the scanner evidently accepts it, but it should be confirmed
    rather than assumed. One line in `topup_qr_payment_page.dart`.
30. **No live top-up has been filed from this build.** Everything is unit-
    tested and the flow compiles and runs, but `POST /topup` has never been
    exercised end to end from here. Worth doing before the flow is offered to
    customers — the same caveat #12 carried for `/ploan` until 2026-08-17.
    A top-up also files against a **real contract**, so pick a test customer.
31. **`max_transfer_amount` gates every contract.** Absent or 0, no payout is
    under it and **every** contract falls to the lead branch (see **Top-up
    flow**). Confirm `/loan/list` actually sends it on uat before reading a
    screen full of ส่งข้อมูล as a bug in this code.
32. **Mock mode covers the top-up flow, and its write paths are guarded.**
    `--dart-define=P_LOAN_MOCK=true` serves the P-Loan fixtures through
    `TopupApi`'s delegating methods, plus `mockTopupStatus` for the status
    screen. ⚠ The guard on `submit` / `payInterest` / `saveLead` is the
    load-bearing part: without it a *demo* build would really file a top-up,
    really raise an interest payment and really create a lead, because those
    three are `TopupApi`'s own implementations rather than delegates to the
    already-guarded `PLoanApi`. A test asserts every one of them still has it —
    don't add a `/topup/*` write without one.

33. **`POST /GetRecalTopupData` is on a temporary test host.** `34.142.213.42:8080`
    is what the API team stood up while the real endpoint is built; **the QA
    endpoint follows**, and when it lands this all gets simpler. Today the test
    host is plain HTTP on an IP, sends no CORS headers, 401s the preflight and
    authenticates with a **shared `Basic` service account** — so a browser
    cannot reach it, and the credential that would make it reachable must not
    ship in the bundle.

    **The host allowlist half is done** (2026-09-12, on request):
    `http://34.142.213.42:8080/` is in `_kHttpRequestAllowedPrefixes` plus a
    scoped Android cleartext exception, committed as `4ea8f79` on
    `pentest_resolved` in the srisawad repo — **local only, the push needs
    VPN** — and ⚠ still needs an app release to reach a device (same constraint
    as #10). Both edits carry a removal checklist; the host repo's CLAUDE.md
    has it under **Temporary top-up recalculation host**. **Delete them when
    the QA API is ready** — that is the explicit instruction, not a nice-to-have.

    **The credential half is deliberately not done.** `TOPUP_RECAL_API_AUTH`
    ships empty, so even inside an allowlisted build the client makes no call
    and the section stays hidden. Passing it at build time
    (`--dart-define=TOPUP_RECAL_API_AUTH='Basic …'`) is what turns the section
    on for a test; note that puts a shared service account into a readable web
    bundle for as long as that build is deployed, which is why it is a
    per-build choice rather than a default.

    **The real fix is the QA endpoint being on the mobile API base** — HTTPS,
    `access-control-allow-origin: *`, the customer's own bearer token, the way
    `POST /ploan` went in 2026-08-04. That closes the credential question, the
    CORS question and the cleartext question at once, and lets the host
    allowlist shrink back. Until then the ยอดที่ต้องชำระเพื่อเติมวงเงิน section
    is simply hidden — the client returns `null` rather than failing the
    screen. See **`POST /GetRecalTopupData`**.

### Pentest 2026-08-11 → passed (`pentest_doc/`)

**The retest passed; all findings are signed off** (2026-08-25). "Passed" is
not "nothing left to hold": several were closed by the API and infrastructure
teams rather than here. The full list, and what each sign-off does and does not
cover, is in [docs/HISTORY.md](docs/HISTORY.md#pentest-2026-08-11).

⚠ `pentest_doc/` and the `Digital Lending with Srisawad_V2.0` PDF are
**git-ignored** — 43 MB of binaries, and a findings report is a map of this
system's weak points. Same rule as `api_data/`, `ndid_doc/` and `etc/*.txt`:
they live in the working copy, never in the remote.

Three of them still constrain what you may change here:

- **🐞 Finding #11 (NDID validated client-side) — the client shipped only the
  *prerequisite*.** `PLoanFlow.ndidReferenceId` reaching `POST /ploan` is what
  makes a server-side check *possible*; the check itself is the API team's. So
  if the NDID hop is ever touched, **re-check that the reference still reaches
  `/ploan`** — dropping it would silently return the system to the state the
  tester exploited, and the client would look no different.
- **🐞 The plain-browser NDID hop is a bypass in its own right — still open.**
  `ndid_verify_page.dart`'s “จำลองยืนยันตัวตนสำเร็จ” button sets verified with **no
  NDID traffic at all**, and renders whenever `NativeCameraBridge.isSupported`
  is false — i.e. in any browser that opens the deployed URL. Photos fall back
  to `image_picker`, so the whole Extra completes without NDID and needs no
  interception. Fix is an `NDID_SIMULATE` define defaulting to false (same
  shape as `kPLoanUseMockData`), with a test pinning it off.
  ⚠ **Verified present 2026-08-25** at `ndid_verify_page.dart:442`. It was
  never in the report, so nobody tested for it — do not read “pentest passed”
  as covering it.
- **`REQUESTED_ERROR` / `IDP_OR_AS_ERROR` were treated as pending** by
  `NdidVerifyStatus.isPending`, polling a dead request for the full hour. Now
  handled — see **NDID Common Message standard**. Not a pentest finding;
  noticed alongside them.

## Conventions

- Thai UI strings inline; English code/comments.
- All styling goes through `LoanRegisterStyles` + `google_fonts` NotoSansThai.
- Build/verify with `flutter analyze --no-pub`, `flutter test`, and
  `flutter build web --release --pwa-strategy=none`. New model fields → update
  both `fromJson` and `toJson` (and `copyWith`).
