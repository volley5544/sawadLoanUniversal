# Sawad Loan Universal

Flutter app for a Thai loan-application (**สมัครสินเชื่อ**) flow.

**Deployment model:** this is built as a **Flutter web** app and embedded inside
a separate **native Flutter app** via
[`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview) (the
native host opens this web build in a WebView). The Android/iOS/desktop
scaffolding still exists, but the **web build is what ships**.

> **Two features at different stages.** The 5-step wizard is **UI-only** — no
> backend submit; its screens render from mock data plus a customer profile the
> native host provides. The **P-Loan application flow**
> (`lib/p_loan/application/`) is **live end to end** against the srisawad mobile
> API, with no mock fallback. UI text/data is Thai; code comments are English.
>
> See [CLAUDE.md](CLAUDE.md) → **Outstanding** for what is still blocked and on
> whom. As of **2026-08-04** both kinds file with `POST /ploan` — a
> bearer-authenticated JSON call on the mobile API base — so the **P-Loan Extra
> is no longer blocked** (the old `httpMultipart`/Basic-credential/`:8082`
> requirements are gone); one live submit is still needed to confirm it end to
> end. A **new P-Loan** remains blocked on a document endpoint for a contractless
> loan.

## Build & run

```sh
flutter pub get
flutter analyze --no-pub                      # only pre-existing flutter_lints infos
flutter test                                  # 157 tests
flutter build web --release --pwa-strategy=none
```

- Output is in `build/web/`. Serve that wherever the native host points its
  WebView.
- Build web with **`--pwa-strategy=none`** so the Flutter service worker doesn't
  serve a stale build inside the WebView.
- **`web/index.html` loads pdf.js** (script + worker + cMaps). `pdfx` needs it to
  render the step-6 contract PDFs; strip those tags and the viewer goes blank
  with no build error to warn you.

## Launch parameters

The native host launches the web URL with a hashed Thai ID and a Firebase auth
token:

```
https://<host>/?hashThaiId=<hash>&token=<firebase-jwt>
```

`main.dart` reads them into `AppState.hashThaiId` / `AppState.authToken`, then
fires a background fetch of the customer profile (`/user/detail`) and address
book (`/profile/address`) so step 1 of the wizard auto-fills. While that fetch
is in flight, `AppState.profileLoading` is `true` and step 1 shows a blocking
loading overlay ("กำลังโหลดข้อมูลลูกค้า...") — so the user knows data is
loading and can't type into fields the fetch is about to overwrite.

Address cards on step 1 treat the address API as **authoritative per address
type**: if the address book loaded but a block is empty, the card shows
**blank** (no data invented). The profile's single address is only a stopgap
when the address book is missing entirely (fetch failed or still loading).

## The wizard

A 5-step loan-register flow under `lib/loan_register/` (the step indicator
shows 1–5):

1. **ข้อมูลลูกค้า** — customer info (auto-filled from the profile)
2. **ข้อมูลหลักประกัน** — collateral info (+ document/OCR capture)
3. **ข้อมูลสินเชื่อ / ข้อมูลการโอนเงิน** — loan & transfer info. Opens two
   full-screen **sub-selectors**: **จำนวนงวด** (installment picker) and
   **ประเภทการโอน** (transfer-type picker) — these are *not* separate wizard
   steps, just pickers that pop their value back.
4. **เอกสารแนบ** — document attachments, then **ลงนาม + ยืนยันตัวตนผ่าน NDID**
   (sign + identity verification). See below.
5. **นัดหมายส่งเอกสาร** — document-delivery appointment.

### Step 4 — เอกสารแนบ + NDID (slides 8–9)

Built from slide 8 ("ขั้นตอนที่ 3 ยืนยันตัวตนผ่าน NDID") and slide 9's first
frame. The customer attaches documents, then reviews + signs the contract
documents and verifies their identity via NDID:

```
document_attach_page  (Step 4: เอกสารแนบ)
  └─ ตรวจสอบเอกสาร → document_review_page   (acknowledge + sign)
       └─ ndid_terms_page                   (NDID service agreement)
            └─ ndid_bank_select_page        (pick the IDP bank)
                 └─ ndid_verify_page        (countdown → ยืนยันตัวตนสำเร็จ)
```

`ndid_verify_page` pops `true` back up the chain; that flips the contract-docs
card on step 4 to its verified state (green check + ดาวน์โหลดเอกสาร) and unlocks
the bottom **ถัดไป** → step 5. The NDID verified flag lives on
`LoanRegisterForm.ndidVerified`.

The three NDID screens are **shared with the P-Loan flow's step 6**: they take
a `NdidSubject` (`lib/models/ndid_subject.dart`), which both `LoanRegisterForm`
and `PLoanFlow` implement, so neither flow needs a copy of them.

`ndid_terms_page` is the sub-flow's entry point (added 2026-08-28) — the NDID
service agreement, read as **one continuous scroll** and answered ยอมรับ /
ปฏิเสธ. Its wording is generated from the supplied Apple Pages document into
`lib/loan_register/ndid_terms_content.dart` rather than retyped. ยอมรับ goes on
to the IdP picker and passes its result straight back, so both callers still
just await one bool.

> The **bank's own app** screens (K+ PIN pad, NDID provider consent/terms) are
> **third-party — not rebuilt here**. `ndid_verify_page` simulates that hop with
> a "จำลองยืนยันตัวตนสำเร็จ" button; a real integration would receive the IDP
> callback instead.

### Step 5 — นัดหมายส่งเอกสาร (slide 9, left 3 frames)

```
appointment_page  (Step 5)
  └─ "เพิ่ม สาขาและวันที่-เวลานัดหมาย" → documents_to_prepare_page
       (เอกสารที่ต้องเตรียมวันนัดหมาย checklist)
```

`documents_to_prepare_page` returns a representative appointment
(`{branch, dateTime}`) to the appointment list. The **branch map-search and
date/time calendar** screens (slide 9, right frames) are **out of scope** and
not built. Step 5's **ถัดไป** is the end of the (UI-only) flow — it shows a
"บันทึกข้อมูลเรียบร้อย" SnackBar; no backend submit yet.

## P-Loan application flow

A **6-step wizard** (`lib/p_loan/application/`, entry route `/pLoan/contract`,
home-menu card **ขอสินเชื่อส่วนบุคคล**): เลือกสัญญา → ยอดจัดสินเชื่อ → จำนวนงวด
→ รูปภาพหลักประกัน → ตรวจสอบข้อมูลส่วนตัว → สรุป/ยืนยัน. Unlike the rest of this
repo it is wired to live APIs with **no mock fallback** — see
`lib/services/p_loan_api.dart`.

**Two ways in** (`PLoanEntry`). Normally step 1 from the home menu. The
**LandAndHouseWeb top-up card** instead deep-links to
`/pLoan/resume?dbName=…&contractNo=…`, which rebuilds what steps 1–2 would have
produced and lands on **step 3**, then goes **3 → 5 → 6**: the card already
showed the amount (so step 2 is redundant) and an Extra's collateral is already
on file from `/loan/list` (so step 4 is). The indicator counts **the top-up card
itself as step 1** and so runs 2/4 → 3/4 → 4/4: the skips don't read as a bug,
and the screen the customer came from isn't disowned. Both step 3's back button
and the success screen close the WebView back to the card. The requested amount is
`/topup/detail`'s `topup_extra` — the **same** fixed offer step 2 uses, so both
entry points quote one amount.

Walkable in a plain browser (the mobile API sends `access-control-allow-origin:
*`), which is the easiest way to test it:

```
https://sawad-loan-universal-uat.web.app/pLoan/resume?hashThaiId=<HASH>&token=<JWT>&dbName=<DB>&contractNo=<NO>
```

It spans three projects, all **built** as of 2026-07-30: this one, the native
host (needs an app release to reach testers), and LandAndHouseWeb's
`openPLoanExtra` custom action. The real chain has been walked on a device
through NDID signing; **no live submit has been made yet** — see the blocker
below.

Inside the app there are now **two triggers** for the same `/pLoan/resume`:
LandAndHouseWeb's top-up card (via `srisawad://ploan-extra`, which the host
intercepts) and the srisawad home screen's **LoanCard → สิทธิพิเศษเฉพาะคุณ** chip
when `product_code == 'PLD001'`, which pushes the route natively.

⚠ Skipping step 4 also means **no collateral photos are submitted**.
All of it — the snippets, the host edits, the mock test URLs and what
`topup_extra` turned out to mean — is in [CLAUDE.md](CLAUDE.md) → *Two entry
points* and *Outstanding*.

Step 1 offers **two products** (`PLoanKind`), which then share all six screens:

- **สินเชื่อเพิ่มจากสัญญาเดิม** (P-Loan Extra) — the contract carousel. More
  money against a contract the customer already has. The amount is **fixed** at
  `topup_extra` (the วงเงินเพิ่มเติม the top-up card advertises) and the field is
  read-only — this product lends the offer rather than letting the customer size
  it. `min/max_topup_amount` are **not** applied: they bound the top-up product,
  which this is not.
- **ขอสินเชื่อใหม่** (new P-Loan) — the card above it. A fresh loan whose amount
  **starts blank** for the customer to type, with no limit inherited from a
  contract. (Neither product deducts an old principal — the payout is
  `request − stamp duty` for both, since neither replaces an existing contract.)

**A new P-Loan has no contract at all.** `refContractNo` ("เลขที่สัญญาอ้างอิง")
is an Extra's field — it names the contract the top-up is raised against — and a
new P-Loan is raised against nothing. So the new-loan card is offered **even to a
customer with no contracts**, and an empty `/loan/list` only rules out the Extra.

Everything that would otherwise come off a contract is either asked for or
unavailable:

- **The customer enters it.** Step 4 asks for the collateral type (which decides
  which photos are required) plus ยี่ห้อ / รุ่น / ปีที่ผลิต and optional plate
  details; step 5 asks for the payout bank, account number and account name.
  Both gate the submit.
- **Pricing is an interim client-side estimate.** Steps 2–3 make no `/topup/*`
  call — all of them are keyed by `db_name` + `contract_no` — so until the
  new-P-Loan calculator API exists, step 3 shows a provisional estimate computed
  on the amount entered.
- ⚠ **The contract documents can't be generated**, because `POST /pdf/loan` is
  keyed by a contract too. Step 6 says so in place and **a new-loan submit
  cannot complete yet**; the Extra path is unaffected.

**Both kinds submit to `POST /ploan`** (`lib/services/p_loan_contract_api.dart`)
since 2026-07-31 (unified endpoint), **retargeted 2026-08-04** to a
mobile-API-style call: base from `api_url['api_url_base']`, the customer's
Firebase **bearer token** for auth, `x-srisawad: x1`, JSON body. An Extra used to
post `/topup`, inherited from the FlutterFlow source where the whole feature was
a top-up wearing P-Loan naming — but a P-Loan Extra is a P-Loan *contract* that
references an existing one, not a top-up of it. `refContractNo` is now the only
field separating the two kinds.

The retarget **unblocked the Extra**: the old endpoint's multipart body, missing
CORS, `httpMultipart` bridge requirement and baked-in Basic credential are all
gone. One live `/ploan` submit is still needed to confirm it end to end.

See [CLAUDE.md](CLAUDE.md) → **P-Loan save API** and *A new P-Loan has no
contract at all* for the full picture.

Step 6 shows the three contract PDFs from `POST /pdf/loan` **inline**, rendered
by `pdfx` through pdf.js (loaded in `web/index.html`) rather than by the
embedder's own PDF plugin — Android WebView has none, and the previous
`<iframe>`-over-a-Blob viewer showed a blank frame there. The customer reads and
consents in the app: there is deliberately **no download and no open-externally**
action, both commented out rather than deleted.

It then ends with an **NDID** hop — the customer signs the contract documents
with their bank identity, reusing the wizard's own NDID screens (they take a
`NdidSubject`, which both flows implement). It gates the submit. `/idp/list` and
`/rp/verify` share one pair of assurance levels (`NdidApi.minIal` 2.3 /
`minAal` 2.2), and **every environment verifies the applicant's own Thai ID**.
The non-prod test-identity substitution was deleted on 2026-07-31 once the uat
gateway gained real identities; a customer who has onboarded with no IdP now
correctly gets an empty "registered" bank grid instead of a usable mock one.

API endpoints are read at startup from the Firestore document
**`application/public_config`** — the mobile API from `api_url.api_url_base` and
the **NDID gateway** from `api_url.ndid_url_base` — authenticated with an
**anonymous** Firebase identity minted over REST; there is no Firebase SDK in
the app. Each falls back to its compile-time value (`AppEnvironment.mobileApiBase`
/ `kNdidApiBase`) if that read fails, and it never blocks boot. The secrets live
in a *separate* `application/config` document that no client rule grants access
to; `firestore.rules` is checked in and deployed to both projects.

⚠ Moving `ndid_url_base` needs a matching change in the **host app**: NDID is
proxied through its `httpRequest` bridge, which only calls allowlisted hosts. See
Outstanding #22 in `CLAUDE.md` — uat currently points at a gateway the shipped app
still rejects.

Payload mapping: `PLoanContractSubmission.fromFlow(flow)` builds the 30 fields
`SavePloanContract` takes, and `PLoanSubmission.fromFlow(flow)` the 34 that
`regmast_ploan.php` does — the shared values are read back from the latter so the
two can't drift. Fields with no source in this flow are reported in
`unresolvedFields` rather than guessed.

Ported from the FlutterFlow app's `lib/p_loan`, which turned out to be an
unfinished copy-paste fork of its top-up flow: the submit was unreachable, step
2's amount input never rendered, and the ID check accepted four hardcoded Thai
IDs. All three are fixed/removed here — the details and the remaining naming
caveat are in [CLAUDE.md](CLAUDE.md).

## P-Loan submission form

Separate from the wizard, a **standalone** form (home-menu card **สมัครสินเชื่อ
P-Loan**, route `/pLoanFormPage`) whose fields map **1:1** to the legacy
`regmast_ploan.php` submission API. `lib/p_loan/submit_form/p_loan_form_page.dart` renders 34
scalar fields (seeded with sample values) plus 12 image-attachment groups. Each
group's **แนบรูป** button asks for a source (ถ่ายรูป / เลือกรูปจากคลังภาพ): the camera
uses the native bridge inside the host and `image_picker` elsewhere, the gallery
always uses `image_picker` — so attachments also work in a plain browser.
`lib/services/p_loan_api_service.dart` builds the `multipart/form-data` POST
(scalar fields + repeated `key[]` file parts) mirroring the original PHP `curl`
call. **ดู Payload** previews the request; **ส่งข้อมูล** submits. The endpoint is
internal HTTP on a private IP (`10.1.112.74`), so a live submit only works from
inside the host network — the Payload preview works anywhere.

## Document / OCR capture (web ↔ native camera)

The web build has **no camera**; the document photo is captured by the **native
host's** camera so it gets a proper masked camera UI. The web asks for a capture
via `flutter_inappwebview`'s `callHandler` and awaits the result:

```dart
// lib/services/native_bridge.dart  (web impl in native_bridge_web.dart)
final base64 = await NativeCameraBridge.captureDocument('collateral');
// -> window.flutter_inappwebview.callHandler('openCamera', 'collateral')
```

`captureDocument` returns `Uint8List?` (`null` = cancelled). It's a no-op outside
the WebView host (`NativeCameraBridge.isSupported` is `false` in a plain
browser, so the UI shows a "ใช้ได้เฉพาะในแอป" message).

### Native host implementation

The embedding app registers an `openCamera` JS handler that opens its camera for
the requested mask type and **returns the photo as a base64 string** — that
value resolves the awaited Promise on the web side:

```dart
webViewController.addJavaScriptHandler(
  handlerName: 'openCamera',
  callback: (args) async {
    final action = args.isNotEmpty ? '${args.first}' : ''; // 'collateral', 'idcard', ...
    final bytes = await openNativeCamera(action);          // your masked camera
    if (bytes == null) return null;                        // user cancelled
    return base64Encode(bytes);                            // resolves the JS Promise
  },
);
```

Tips for the host:
- Return a plain `String` (or `null`) — not a `Uint8List`.
- The `async` callback is fine; the Promise resolves when the `Future` completes.
- Compress the photo (~1280px / JPEG ~80) before base64 to keep the bridge fast.
- Camera permission is needed by the **host app** (Android `CAMERA`, iOS
  `NSCameraUsageDescription`) — not WebView `getUserMedia`, since the camera is
  native.

The full handler example also lives in the doc comment of
`lib/services/native_bridge.dart`.

## Project layout

```
lib/
  main.dart                     app entry; launch params; warms runtime config
  app_state.dart                ChangeNotifier singleton; persists CustomerDetail
  models/
    customer_detail.dart        plain-Dart API model (snake_case JSON)
    ndid_subject.dart           what the shared NDID screens need from a flow
    app_config.dart             the Firestore runtime-config document
  services/
    native_bridge.dart          public entry (conditional import)
    native_bridge_web.dart      web impl (flutter_inappwebview callHandler)
    native_bridge_stub.dart     non-web stub (throws / isSupported=false)
    api_transport.dart          shared HTTP + multipart, bridge-aware
    p_loan_api_service.dart     regmast_ploan.php multipart client
    srisawad_api.dart           shared base URL / headers / GET /loan/list
    topup_api.dart              top-up API group (/topup/*)
    p_loan_api.dart             P-Loan API group (the flow's single seam)
    p_loan_contract_api.dart    P-Loan save API (POST /ploan, bearer +
                                multipart: 31 fields + 5 file parts)
    app_config_api.dart         Firestore runtime config (REST, no SDK)
    firebase_auth_rest.dart     anonymous sign-in over REST (no SDK)
    firestore_rest.dart         typed-value decoder for the REST format
    diagnostics.dart            breadcrumb trail across reloads + a readable
                                error screen (tap the "(UAT ver…)" tag)
    device_location.dart        GPS for the submit payload (+ _web / _stub)
  loan_register/
    *_page.dart                 the wizard steps & pickers
    ndid_terms_page.dart        NDID service agreement — the NDID sub-flow's
                                first screen, shared with P-Loan step 6
    ndid_terms_content.dart     its wording, generated from the Pages document
    models/loan_register_form.dart   in-memory wizard model (+ mock data)
    components/                  shared field rows, styles, step indicator, etc.
  p_loan/
    submit_form/                standalone P-Loan form (regmast_ploan.php API)
    application/                6-step P-Loan application flow (mobile API)
      p_loan_topup_card_resume_page.dart
                                deep-link entry from the LandAndHouseWeb
                                top-up card; rebuilds the flow, opens step 3
firestore.rules                 deny-by-default + one client-readable document
tools/firestore-import/         seeds appConfig from a console-export dump
tools/deploy-uat.sh             manual deploy to uat (the Stop hook that
                                ran it no longer exists — CI owns uat now)
```

## Recent changes — 2026-08-28

**NDID now opens with its service agreement.** A new screen,
**เงื่อนไขและข้อตกลงที่เกี่ยวข้อง NDID** (`lib/loan_register/ndid_terms_page.dart`),
is the first step of the NDID sub-flow — ahead of the IdP picker, in **both**
the wizard's step 4 and the P-Loan flow's step 6.

- The agreement is **one continuous scroll** with ปฏิเสธ / ยอมรับ pinned at the
  bottom. It was first built as the design showed it — a three-page `PageView`
  with a `1 of 3` counter — and changed on request. The scroll is also the
  sturdier shape: Flutter web leaves the **mouse** out of a `PageView`'s
  `dragDevices`, so in a desktop browser the later pages could not be swiped to
  at all.
- ยอมรับ continues to the IdP picker and passes that chain's result **straight
  back**, so `document_review_page` and `p_loan_conclusion_page` still just
  `await` one bool — neither caller changed shape. ปฏิเสธ ends the hop.
- The wording is **generated, not retyped**, from the supplied Apple Pages file
  into `ndid_terms_content.dart` (a `.pages` file is a zip whose
  `Index/Document.iwa` is Snappy-framed protobuf). Clause numbers are structural
  data, because the document itself only wrote some of them — 3, 4 and 6–9 had
  literal digits while 1, 2 and 5 were auto-numbered by Pages.
- ⚠ A **decline is logged to the session only** (`Diagnostics.log`), which is
  in-memory and gone when the WebView closes. The design's
  "กรณีปฏิเสธมีเก็บ log" note probably wants a server-side record; no endpoint
  exists for one — see CLAUDE.md → Outstanding #23.

Tests: `test/ndid_terms_content_test.dart` pins clauses 1–9, clause 3's five
sub-items and that no clause re-renders its own number;
`test/ndid_terms_page_test.dart` renders the screen at phone size and scrolls
from the first clause to the last.

## Recent changes — 2026-08-07 → 2026-08-25

Three sessions, ending with the **2026-08-11 pentest signed off** and the first
**live `POST /ploan` submit**. Full detail in [CLAUDE.md](CLAUDE.md); the
headlines:

**Security — the pentest retest passed**

- **Every `api_url_base` call now carries the bearer token.** `GET /user/detail`
  — a customer's own profile — had been going out unauthenticated from all three
  of its call sites, and it is the endpoint finding #2 names first. `token` is now
  a **`required` argument** on every client method, so the compiler is the guard
  rather than a convention; an empty one logs a warning instead of sending a bare
  `Bearer `. Pinned by `test/srisawad_api_headers_test.dart`.
- **The NDID reference reaches the payload.** `ndid_reference_id` — NDID's own
  `reference_id` for the accepted verification — is filed with the application so
  the backend can confirm the result with NDID instead of trusting a client bool.
  ⚠ That is the **prerequisite** for finding #11, not the fix; the server-side
  check is the API team's. It is written only on the real API path — the
  simulated hop records nothing rather than claiming a verification that never
  happened.
- No baked-in service credential ships any more (deleted 2026-08-04 with the
  bearer retarget). `kNdidApiKey` is the only one left, and a web build cannot
  hide it regardless.
- ⚠ **Still open, and never part of the report:** the plain-browser
  "จำลองยืนยันตัวตนสำเร็จ" button is a real NDID bypass in any build a browser can
  reach. "Pentest passed" does not cover it — nobody tested for it.

**🐞 The iOS white screen — root cause found and fixed**

- **The NDID bank-select page was crashing the WKWebView content process**, in
  the foreground. Each bank logo is an HTML `<img>` **platform view** (it has to
  be — the gateway sends no CORS headers and its placeholder is an SVG), and in
  CanvasKit every platform view gets its own GPU-backed overlay canvas, ~12 MB at
  phone DPR. The uat gateway returns **16** IdPs and both grids render eagerly,
  so all 16 arrived at once — past what one content process gets.
- **Fixed by rationing logos** to four tiles, registered grid only; the rest fall
  back to initials. Shipped as uat **webVersion 74**. ⚠ The deciding test is
  still outstanding: an iOS tester **lingering 30–60 s** on that page. A run that
  taps through in ~3 s beats the image loads, which is why it looked intermittent.
- **New: on-device diagnostics** (`services/diagnostics.dart`) — a breadcrumb
  trail that survives a reload, plus a readable error screen in place of
  Flutter's textless grey box, reachable by tapping the `(UAT ver…)` tag. This is
  what proved the cause: the bad run's trail ended at `push /ndidBankSelectPage`
  with **no `ERROR` crumb** (nothing threw) and **no `lifecycle hidden`**
  (foreground), which is the signature of a process kill rather than a crash.
  ⚠ The copied report masks `token` and `hashThaiId` — keep it that way.
- **`pdfx` never closed its documents.** `PdfController.dispose()` disposes only
  its `PageController`, so all three contract PDFs stayed resident in the pdf.js
  worker from step 6 onward. A real leak, now released along with the
  rendered-page bitmaps — but **not** the white screen's cause.

**P-Loan save (`POST /ploan`)**

- **A live submit succeeded** (2026-08-17, contract `SLOAN`) — the first ever. It
  settled in one shot what nothing on paper could: the endpoint accepts
  `multipart/form-data`, the CORS preflight passes, and the five-file body size
  passes.
- **The body is `multipart/form-data` again**, with five real file parts — the ID
  card, the selfie, and the three consented contract PDFs. Unlike the old `:8082`
  endpoint this needs **no `httpMultipart` bridge handler and no app release**:
  `/ploan` sends `access-control-allow-origin: *`, so the upload goes direct
  through `package:http` (`bypassHostBridge: true`).
- **`latitude` / `longitude` come from the device GPS** now
  (`navigator.geolocation`, captured un-awaited on the submit screen). No host
  change was needed — the host already grants geolocation. A denial or timeout is
  silent by design: the fields stay empty and the application still files.
- **Five fields are blank on purpose**, no longer reported as unresolved: the two
  GPS ids (they need a reverse lookup into srisawad's own id set that no endpoint
  here provides) and the three host launch params a customer-initiated
  application simply has none of.
- **`/pdf/loan`'s `x-srisawad` override is prod-only** since 2026-08-07 — uat
  sends the ordinary `x1` there like every other call.

`flutter analyze` sits at its 39-info baseline (no errors or warnings) and
`flutter test` is green at **157 tests**.

## Recent changes — 2026-08-04

A session aimed at pentest-readiness and pointing the P-Loan save at the new uat
gateway. Full detail in [CLAUDE.md](CLAUDE.md); the headlines:

**P-Loan save endpoint → `POST /ploan`**

- **Retargeted** from `<:8082>/SavePloanContract` (multipart, a shared HTTP Basic
  credential baked into the bundle) to a **mobile-API-style call**: base from
  `api_url['api_url_base']` in the Firestore config (uat: `dev.swpfin.com:7076`),
  the customer's **Firebase bearer token** for auth, `x-srisawad: x1`, and a JSON
  body — the 30 fields, unchanged, matching the supplied curl.
- This **deleted the shared Basic credential** (`kPLoanSaveApiAuth`) and the
  `:8082` host define from the source — no shared secret ships in the bundle now,
  closing that pentest finding (verified gone from the live `main.dart.js`).
- It also **removed the submit blocker**: the never-built `httpMultipart` bridge
  handler and the `:8082` allowlist entry are no longer needed, so the **Extra
  can complete**. (One live `/ploan` submit still needed to confirm reachability
  and CORS.)

**uat API headers & timeout**

- **`x-srisawad: x1` on every `api_url_base` call.** The new uat gateway requires
  it (the old host did not); set once at `AppEnvironment.uat.srisawadHeader`, the
  single chokepoint `SrisawadApi.headers()` reads. `pdf/loan` used to override
  this with `x1_c3Jpc2F3YWQ` everywhere; **since 2026-08-07 that override is
  prod-only** and uat sends the ordinary `x1` there too
  (`AppEnvironment.pdfLoanSrisawadHeader`).
- **`sendApiRequest` timeout 30 s → 60 s**, giving the `/ploan` contract-filing
  POST headroom (it no longer rides the old 120 s multipart path). NDID keeps its
  own separate 30 s timeout.

**NDID bank select**

- **The "ยังไม่ลงทะเบียน NDID" grid is now selectable**, like the registered one.
  `_next` never branched on which grid a bank came from, so an unregistered IdP
  goes through the identical `POST /rp/verify`; the bank app then walks the
  customer through sign-up before verifying. A customer with no onboarded IdP is
  no longer stuck at a dead end.

**Pentest prep (LandAndHouseWeb, the sibling FlutterFlow project)**

- Removed **all debug `print`/`debugPrint`** from that project (99 statements
  across 45 files), **keeping** the `Volley5544`-marked console prints the native
  host parses as its web↔app bridge. Analyzer stayed at 0 errors.

**Docs**

- The **P-Loan Extra user manual** (`docs/`) was re-shot on a real device against
  live uat and given three new screens; identifiers are pixelated throughout.

## Recent changes — 2026-07-31

A session spent getting the NDID hop working against the **real** uat gateway,
plus one product decision. Full detail in [CLAUDE.md](CLAUDE.md); the headlines:

**NDID**

- **Gateway URL is config-driven.** `NdidApi.baseUrl()` reads
  `api_url.ndid_url_base` from the Firestore runtime config, falling back to
  `kNdidApiBase`. The uat document now points at a real NDID node with real banks
  and real identities.
- **Every environment verifies the applicant's own Thai ID.** The non-prod
  test-identity substitution (`kNdidTestThaiId`) is **deleted**, not disabled —
  the literal no longer appears in the bundle.
- **`request_type` is no longer sent.** It is optional on both gateways and their
  valid sets are disjoint, so a hardcoded value was a `20091` waiting to happen.
  Still settable via `ndid_request_type` / `--dart-define=NDID_REQUEST_TYPE`.
- **Bank tiles show the gateway's logos** (`logo_url`), rendered through an HTML
  `<img>` because the gateway sends no CORS headers and its placeholder is an
  SVG. The no-logo fallback is initials, not the node id — this node's ids are
  UUIDs, which overflowed the 44×44 tile.
- **The verify page detects results reliably now**: it re-polls on resume (a
  backgrounded WebView suspends timers), has a manual ตรวจสอบสถานะ button,
  surfaces poll failures instead of swallowing them, stops polling when the
  countdown ends, and **stays inside the gateway's 100-requests-per-900s limit**
  (3 s for 30 s, then 15 s; 60 s back-off on 429). The old flat 3 s poll was 3×
  over and went blind for ~40 of the 60 countdown minutes.

**Config**

- 🐞 **The Firestore runtime config had never loaded inside the app.** Every
  request went through the host's `httpRequest` bridge, whose allowlist omits
  Google's hosts, so sign-in was rejected and the config silently resolved empty.
  Nobody noticed because uat's `api_url_base` equals the compile-time default —
  it only surfaced when `ndid_url_base` named a different host. Those two calls
  now bypass the bridge (they are CORS-enabled), and `main.dart` logs the
  **resolved** endpoints with a `(config)`/`(default)` label.

**P-Loan**

- **Both kinds now file with `POST /SavePloanContract`.** An Extra is a P-Loan
  contract that *references* an existing one, not a top-up of it — which settles
  the "rename it if that's wrong" note this port carried from the FlutterFlow
  source. Side effect: the hardcoded `'Y'` PDPA consents in the dead `/topup`
  body no longer reach anyone.
- Step 5 (Extra 3) shows **ชื่อ-สกุล** above เบอร์โทรศัพท์.

**Still blocked on the host app** — `httpMultipart` handler plus the allowlist
entries, both needing an app release. Until then no submit completes.
*(Superseded 2026-08-04: the save endpoint moved to `POST /ploan`, which needs
neither — see the 2026-08-04 section above.)*


See [CLAUDE.md](CLAUDE.md) for the full architecture notes, conventions, and
known quirks.
</content>
