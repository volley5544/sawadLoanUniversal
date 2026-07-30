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
> whom — most notably a **new-P-Loan submit**, which needs a document endpoint
> for a contractless loan *and* an `httpMultipart` handler in the native host
> before it can succeed. The P-Loan **Extra** path completes today.

## Build & run

```sh
flutter pub get
flutter analyze --no-pub                      # only pre-existing flutter_lints infos
flutter test                                  # 115 tests
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
       └─ ndid_bank_select_page             (pick the IDP bank)
            └─ ndid_verify_page             (countdown → ยืนยันตัวตนสำเร็จ)
```

`ndid_verify_page` pops `true` back up the chain; that flips the contract-docs
card on step 4 to its verified state (green check + ดาวน์โหลดเอกสาร) and unlocks
the bottom **ถัดไป** → step 5. The NDID verified flag lives on
`LoanRegisterForm.ndidVerified`.

The two NDID screens are **shared with the P-Loan flow's step 6**: they take a
`NdidSubject` (`lib/models/ndid_subject.dart`), which both `LoanRegisterForm`
and `PLoanFlow` implement, so neither flow needs a copy of them.

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
host (committed — needs an app release to reach testers), and LandAndHouseWeb's
`openPLoanExtra` custom action. The real chain was walked on a device that day as
far as step 4; **no live `POST /topup` has been made yet**.

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

The two kinds **submit to different endpoints**, because `POST /topup` books
against a contract: an Extra goes there, a new P-Loan goes to the P-Loan save
API (`POST /SavePloanContract`, `lib/services/p_loan_contract_api.dart`).
⚠ That endpoint sends no CORS headers, so it also needs an `httpMultipart`
handler on the native bridge that **the host app does not implement yet**.

See [CLAUDE.md](CLAUDE.md) → *A new P-Loan has no contract at all* for all of
this, plus the Basic credential that ships in the web bundle.

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
`minAal` 2.2), and **non-prod builds verify a test identity** rather than the
applicant, because the uat DAP node has no other registered one — prod always
uses the customer's own id.

API endpoints are read at startup from the Firestore document
**`application/public_config`** (`api_url.api_url_base`), authenticated with an
**anonymous** Firebase identity minted over REST — there is no Firebase SDK in
the app. It falls back to the compile-time `AppEnvironment` value if that read
fails, and never blocks boot. The secrets live in a *separate*
`application/config` document that no client rule grants access to; `firestore.rules`
is checked in and deployed to both projects.

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
    p_loan_contract_api.dart    P-Loan save API (POST /SavePloanContract)
    app_config_api.dart         Firestore runtime config (REST, no SDK)
    firebase_auth_rest.dart     anonymous sign-in over REST (no SDK)
    firestore_rest.dart         typed-value decoder for the REST format
  loan_register/
    *_page.dart                 the wizard steps & pickers
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
tools/deploy-uat.sh             Stop-hook auto-deploy to uat
```

See [CLAUDE.md](CLAUDE.md) for the full architecture notes, conventions, and
known quirks.
</content>
