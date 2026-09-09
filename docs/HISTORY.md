# History — Sawad Loan Universal

Archived detail lifted verbatim out of `CLAUDE.md` on **2026-09-09**, when
that file passed the 150k-character limit Claude Code loads per session.

**Nothing here is current behaviour.** Each entry is either a resolved issue,
a design that was replaced, or the evidence behind a decision. `CLAUDE.md`
keeps the conclusion and the warnings and links here for the account. This
file is **not** `@`-imported — read it when a change touches the area, not
every session.

⚠ The `#N` numbering in the Outstanding entries below is `CLAUDE.md`’s and is
cross-referenced throughout it. Do not renumber either list.

## Contents

- [CI owning the uat deploy: cancelled runs and jumping version numbers](#ci-deploy-consequences)
- [`ndid_terms_page`: the three-page `PageView` that was replaced](#ndid-terms-pageview)
- [`ndid_verify_page`: why the four polling behaviours exist](#ndid-verify-polling)
- [`kNdidTestThaiId`: the retired non-prod test-identity substitution](#ndid-test-thai-id)
- [`request_type`: the 20091 that made it opt-in, and each gateway’s set](#ndid-request-type)
- [The iOS white screen: the breadcrumb trail, and what it was not](#ios-white-screen)
- [The FlutterFlow source: what `lib/p_loan` was forked from, and what was dropped](#flutterflow-fork)
- [Outstanding #2 / #3 — `httpMultipart` bridge handler, `kPLoanSaveApiAuth`](#outstanding-2-3)
- [Outstanding #8 / #9 — negative payout, LandAndHouseWeb’s button](#outstanding-8-9)
- [Outstanding #11 / #12 — hardcoded PDPA consents, the first live submit](#outstanding-11-12)
- [Outstanding #14 — `latitude` / `longitude`](#outstanding-14)
- [Outstanding #18 — Android WebView could not render the inline PDF](#outstanding-18)
- [Pentest 2026-08-11 — the full finding list](#pentest-2026-08-11)

---

## <a id="ci-deploy-consequences"></a>CI owning the uat deploy: cancelled runs and jumping version numbers

*Seen 2026-07-31. Summarised in CLAUDE.md under **Deploy**.*

Two consequences of CI owning the deploy, both seen on 2026-07-31:

- **Rapid consecutive pushes cancel each other.** Runs #49 and #50 were 23 s
  apart; #49 was cancelled and only #50 (the branch tip) shipped. Harmless when
  the later commit is a superset, which it was — but "cancelled" in the run list
  is not a failure to chase.
- The version stamp jumps to whatever the run number is, so `WEB_VERSION` is not
  contiguous with what `.deploy-version-uat` last recorded.

---

## <a id="ndid-terms-pageview"></a>`ndid_terms_page`: the three-page `PageView` that was replaced

*Built 2026-08-28, replaced the same day. The lasting point is the second paragraph: a `PageView` on Flutter web cannot be dragged with a mouse.*

  **The agreement is one continuous scroll**, not a pager. A three-page
  `PageView` with a `1 of 3` counter was built first (it is what the design
  showed) and replaced on request the same day. That is also the more robust
  shape: a `PageView` on Flutter web cannot be dragged with a **mouse** — the
  default `ScrollBehavior` leaves `PointerDeviceKind.mouse` out of
  `dragDevices` — so in a desktop browser, which is how this flow is usually
  tested, the later pages were unreachable without adding arrows for them.

---

## <a id="ndid-verify-polling"></a>`ndid_verify_page`: why the four polling behaviours exist

*Reported 2026-07-31 as "status is success but the page keeps counting down". The four fixes are current behaviour and are listed in CLAUDE.md; this is what each one is defending against.*

  **Polling only runs while this page is visible**, and verifying means leaving
  it — the bank's app for a customer, the **NDID UAT console** for a tester
  (enter the ref, set the status to success). A backgrounded WebView has its JS
  timers throttled or suspended, so the 3 s poll is not running while you are
  away, and returning meant waiting on whatever the timer did next. Reported
  2026-07-31 as "status is success but the page keeps counting down". Fixed with
  four changes, all in `ndid_verify_page.dart`:

  - an `AppLifecycleListener(onResume:)` **polls immediately** when the page
    becomes visible again — this is what turns "eventually" into "at once";
  - a **ตรวจสอบสถานะ** button, so a tester never depends on the timer;
  - **poll failures are no longer silent.** They are still ignored individually
    (one flaky response must not kill a live request) but after 3 consecutive
    ones a warning names the error and says it is retrying. Silence here made a
    check that could not reach the gateway look exactly like a customer who
    hadn't approved yet — which is how the DNS outage stayed invisible;
  - the countdown hitting 00:00 now **cancels the poll** and shows the timeout.
    The two timers were independent, so polling outlived the countdown and only
    stopped if NDID happened to report `TIMEOUT`.

---

## <a id="ndid-test-thai-id"></a>`kNdidTestThaiId`: the retired non-prod test-identity substitution

*Lived 2026-07-30 → 2026-07-31. **Do not reintroduce it.** Recorded because the reason it existed (a uat node with one registered identity) is a situation that can recur — and the answer is to register real test identities on the node, never to point the client at somebody else’s id.*

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

---

## <a id="ndid-request-type"></a>`request_type`: the 20091 that made it opt-in, and each gateway’s set

*Settled 2026-07-31. The valid-values table is the reference to come back to if `ndid_url_base` is ever pointed at a different gateway.*

It got here the hard way. The body carried a hardcoded `'Authen Only'`, which the
SIT node accepts and the uat gateway refuses with **`20091 - Invalid request
type`** (hit on a real device right after the bank grid started working). Each
environment publishes its own set at **`GET /request-types`** — wired as
`NdidApi.listRequestTypes()`, kept purely as the diagnostic for a 20091 — and the
sets are **disjoint**:

| Gateway | Valid values |
| --- | --- |
| `dev.swpfin.com/dap` (SIT) | `Authen Only`, `TestRequestType`, `dContract` |
| `uat.ndid.srisawadpower.com` | `dsign.accountopening`, `dsign.dcontract`, `dsign.dcontract.public`, `easyconnext.lineoa`, `idpconnext.thaid` |

---

## <a id="ios-white-screen"></a>The iOS white screen: the breadcrumb trail, and what it was not

*Root-caused 2026-08-17. The cause and the fix (`_kMaxLogoTiles = 4`) are in CLAUDE.md under **On-device diagnostics**. Kept here so the five ruled-out hypotheses are not re-litigated.*

Proven from a tester's breadcrumb trail: it ended at `push /ndidBankSelectPage`
with **no `ERROR` crumb** (no Dart exception) and **no `lifecycle hidden` before
it** (foreground). It only reproduced when the customer lingered — a run that
tapped a bank within ~3 s beat the image loads, which is why it looked
intermittent.

Hypotheses ruled out along the way, recorded so they are not re-litigated:

| Ruled out | Why |
| --- | --- |
| Dart exception / lost go_router `extra` | no `ERROR` crumb, ever |
| Background jettison | no lifecycle change before the death |
| iOS edge-swipe (`allowsBackForwardNavigationGestures`) | a real defect, fixed host-side — but not this |
| The host's stale-version force-reload | `sawad_loan_universal_version_uat` is **5** in the QA Firestore, far below the deployed number, so it never fires |
| The pdf.js document leak | real, fixed (see **Step 6 documents**) — but not the cause |

---

## <a id="flutterflow-fork"></a>The FlutterFlow source: what `lib/p_loan` was forked from, and what was dropped

*The source is `D:\FlutterProject\land_and_house_web_new`, whose `lib/p_loan` is a copy-paste fork of `lib/customer_topup`. Read this before porting anything else across.*

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

---

## <a id="outstanding-2-3"></a>Outstanding #2 / #3 — `httpMultipart` bridge handler, `kPLoanSaveApiAuth`

*Both resolved 2026-08-04 by retargeting the save endpoint to `POST /ploan`.*

2. ~~Implement the `httpMultipart` bridge handler in the host app.~~
   **Resolved 2026-08-04, still resolved 2026-08-07.** The P-Loan save endpoint
   moved to `POST /ploan` on the mobile API base, bearer-authenticated, so it
   needs no multipart handler and no `:8082` allowlist entry. **Both submit
   blockers are gone for the Extra path.** The 2026-08-07 change back to a
   `multipart/form-data` body does **not** reopen this: that handler existed for
   the old host's missing CORS, and this one sends
   `access-control-allow-origin: *`, so the upload goes direct
   (`bypassHostBridge: true`). The remaining verification is a live submit (#12)
   and confirming `/ploan` really does send CORS — which now matters more, since
   a multipart POST with `authorization` + `x-srisawad` triggers a preflight.
3. ~~Do something about `kPLoanSaveApiAuth`.~~ **Resolved 2026-08-04.** The Basic
   service credential was **deleted** when the endpoint moved to bearer auth on
   `/ploan`; nothing shared ships in the bundle now. (`kNdidApiKey` is the only
   baked-in secret left — a web build can't hide it regardless.)

---

## <a id="outstanding-8-9"></a>Outstanding #8 / #9 — negative payout, LandAndHouseWeb’s button

*#8 resolved 2026-07-30. The worked example (`2,000 − 7,740 − 1 = −5,741`) is why `LoanAmountDetail.payoutFor` was deleted rather than deprecated.*

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

---

## <a id="outstanding-11-12"></a>Outstanding #11 / #12 — hardcoded PDPA consents, the first live submit

*#12 resolved 2026-08-17. This is the record of exactly what that one submit proved, which matters because the sample curl proved none of it.*

11. ~~**🐞 `POST /topup` hardcodes both PDPA consents to `'Y'`.**~~ **No longer
    reaches a customer**, as of the 2026-07-31 retarget: `toSubmissionJson()` is
    off every submit path, and `PLoanContractSubmission` — which both kinds now
    use — maps `marketingConsent`/`sensitiveConsent` through `_yesNo`, so a
    declined ยินยอมการตลาด goes out as `N` (verified: a dumped Extra payload shows
    `marketingConsent: "N"`, `sensitiveConsent: "Y"`).
    The literal `'Y'`s **are still in the code** at
    `p_loan_flow.dart:791-792`. Left as-is deliberately: that method is the record
    of the `/topup` wire format, and "fixing" a body nothing sends would only
    disguise the fact that it is dead. If `/topup` is ever revived, fix it *then* —
    or delete the method and this note together.
12. ~~**No live P-Loan save submit has ever run.**~~ **Resolved 2026-08-17** — a
    live `POST /ploan` succeeded against a real contract (`SLOAN`). One submit
    settled every question the 2026-08-07 multipart change opened, none of which
    was specified anywhere (the sample curl is JSON-only and predates the file
    fields, so it proved nothing about any of it):
    - `/ploan` **accepts `multipart/form-data`** and takes the five file parts —
      then under `cardIdImage` / `customerImage` / `documentImage[]`, so
      `_repeatedSuffix`'s `[]` naming assumption holds. ⚠ The two photos were
      merged into `cardIdImage[]` on **2026-09-02**, *after* that submit, so
      that half of the shape is once again unproven on the wire;
    - the **CORS preflight passes**. A multipart POST with `authorization` +
      `x-srisawad` is not a simple request, so the browser sends `OPTIONS` first;
      the mobile API answers it. `bypassHostBridge: true` is therefore right, and
      the `httpMultipart` handler stays unnecessary (#2);
    - the **body size passes** — five files, easily megabytes.

    ⚠ It was **one** submit, from one entry point. A timeout or a request-size
    limit is still the first thing to suspect if a submit that used to work
    starts failing.

---

## <a id="outstanding-14"></a>Outstanding #14 — `latitude` / `longitude`

*Resolved 2026-08-07 via `services/device_location.dart`. `gpsProvinceId`/`gpsAumphurId` remain open and are still in CLAUDE.md.*

14. ~~**`latitude` / `longitude` have no source.**~~ **Resolved 2026-08-07** —
    they now come from the device GPS via `services/device_location.dart`
    (`navigator.geolocation`, captured on step 6). No host change was required;
    see **P-Loan save API**. They still fall back to empty when the customer
    denies location or no fix arrives, which is deliberate.

    **`gpsProvinceId`/`gpsAumphurId` are still open** and having coordinates did
    not resolve them: they are srisawad's own province/district **ids**, so they
    need a reverse lookup from lat/lng to that id set — an endpoint or table this
    app doesn't have. Left blank and reported.

---

## <a id="outstanding-18"></a>Outstanding #18 — Android WebView could not render the inline PDF

*Fixed 2026-07-30 by moving to `pdfx` + pdf.js. Self-hosting pdf.js is the part that remains open.*

18. ~~Android WebView cannot render the inline PDF.~~ **Fixed 2026-07-30** by
    moving to `pdfx` + pdf.js (see **Step 6 documents**). The `openPdf` bridge
    handler this entry used to call for is **no longer wanted** — it would cost a
    host change and an app release to reach a worse UX than a web-only fix that
    is already proven in the top-up flow. What remains is smaller:
    **self-host pdf.js** (`web/index.html` currently pulls 4.6.82 from jsDelivr,
    so a CDN outage blanks the contract viewer again).

---

## <a id="pentest-2026-08-11"></a>Pentest 2026-08-11 — the full finding list

*Retest passed 2026-08-25. The three findings that still constrain changes here are summarised in CLAUDE.md; this is the whole list, including the ones other teams closed.*

### Pentest 2026-08-11 → passed (`pentest_doc/`)

**The retest passed; all findings are signed off** (2026-08-25). The list below
is kept rather than deleted, because "passed" is not the same as "nothing left to
hold": some of these were closed by the API and infrastructure teams rather than
here, and the client's half of finding #11 is a **prerequisite** for the server's,
not a substitute for it. This is what stops a later change quietly reopening one.

⚠ `pentest_doc/` and the `Digital Lending with Srisawad_V2.0` PDF are
**git-ignored** — 43 MB of binaries, and a findings report is a map of this
system's weak points. Same rule as `api_data/`, `ndid_doc/` and `etc/*.txt`: they
live in the working copy, never in the remote.

23. **🐞 Finding #11 — NDID verification is validated client-side.** The tester
    intercepted `GET /rp/verify/{uuid}`, changed `status` to `"ACCEPTED"`, and the
    application filed. Client side, `ndid_reference_id` now goes to `POST /ploan`
    (2026-08-14) — **that is the prerequisite, not the fix.** What closes it is
    server side, and is the API team's: `/ploan` must confirm that reference with
    NDID **server-to-server**, require an `accept` from the IdP at the agreed
    IAL/AAL, bind the NDID request's `identifier` to the bearer token's own
    citizen id (else a genuinely accepted reference can be replayed for someone
    else), refuse a reference already consumed, and refuse a stale one.
    Structural end state: proxy NDID through the mobile API so the client never
    sees or influences the status — that would also close `kNdidApiKey` shipping
    in the bundle, the host-allowlist coupling (#22), and the rate-limit
    gymnastics in `ndid_verify_page.dart`.

    **Status: signed off at the 2026-08-25 retest.** This repo shipped the
    prerequisite; the server-side confirmation is the API team's and nothing here
    can verify it holds. So if the NDID hop is ever touched, re-check that
    `PLoanFlow.ndidReferenceId` still reaches `/ploan` — dropping it would
    silently return the system to the state the tester exploited, and the client
    would look no different.
24. **🐞 The plain-browser NDID hop is a bypass in its own right.**
    `ndid_verify_page.dart`'s "จำลองยืนยันตัวตนสำเร็จ" button sets verified with
    **no NDID traffic at all**, and it renders whenever
    `NativeCameraBridge.isSupported` is false — i.e. in any browser that opens the
    deployed URL. Photos fall back to `image_picker` (a desktop file chooser), so
    the whole Extra completes without NDID and needs no interception. Not reported
    by the pentest; found while tracing #11. Fix is a `NDID_SIMULATE` define
    defaulting to false (same shape as `kPLoanUseMockData`), with a test pinning
    it off.

    ⚠ **Still not done — verified present 2026-08-25** at
    `ndid_verify_page.dart:442`. The retest passing says nothing about this one:
    it was never in the report, so nobody tested for it. Do not read "pentest
    passed" as covering it.
25. **Finding #2 — the server must enforce the auth, not just receive it.** Every
    `api_url_base` call now sends `Authorization: Bearer` (2026-08-14 —
    `GET /user/detail` was the one that didn't; see **API groups**). Sending it
    does not stop anyone calling those endpoints *without* it, which is what the
    finding is about. Server side. **Status: signed off at the 2026-08-25
    retest.** The client's half is pinned by `test/srisawad_api_headers_test.dart`
    plus a `required` `token` argument on every client method, so the omission
    that caused it cannot recur silently.
26. **`REQUESTED_ERROR` / `IDP_OR_AS_ERROR` are treated as pending.**
    `spec.txt:1918-1920` lists them as terminal; `NdidVerifyStatus.isPending` is
    "not accepted/rejected/timeout/cancelled", so either polls for the full hour
    and then reports a timeout. Not a pentest finding — noticed alongside them.
27. **Findings this repo cannot act on** are listed in
    `pentest_doc/SAWAD_Srisawad_Pentest_Findings_20260811.xlsx` and belong to the
    mobile app / API / infrastructure: #1 IDOR, #3 cleartext local storage,
    #4 client-side auth, #5/#8 OTP, #6 brute force, #24 public Firebase Storage
    listing, and the TLS items (#21/#22 in the sheet's numbering — not this
    list's).
