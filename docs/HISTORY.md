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
- [Outstanding #26 — `transaction_ref` seen on a live request](#outstanding-26)
- [Outstanding #27 — `/rp/verify-with-data` verified end to end](#outstanding-27)
- [Outstanding #30 — the first live top-up filed from this build](#outstanding-30)
- [Outstanding #33 — the temporary top-up recalculation host](#outstanding-33)
- [The 2026-09 top-up redesign: provenance, colour rules, reverted experiments](#topup-redesign)
- [`POST /ploan`: the two retargets, and what they deleted](#ploan-save-retarget)
- [`pdfx` 2.9.2 leaks every document the step-6 sheet opens](#pdfx-leak)
- [Step 6's `สรุปยอดสินเชื่อใหม่`, and which `fee_amount` wins](#step6-summary-rows)
- [Pentest 2026-08-11 — the full finding list](#pentest-2026-08-11)
- [The two loan-detail debug dialogs, built and removed the same day](#loan-detail-debug-dialogs)

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

## <a id="outstanding-26"></a>Outstanding #26 — `transaction_ref` seen on a live request

**Closed 2026-09-10.** NDID's review finding 2 required a Transaction Ref of
digits only, at most 9 — and required the *same* number to appear on our
waiting screen and inside the `request_message` the IdP shows. The srisawad
gateway generates it; this app only displays what comes back. Until this run
nobody had seen one arrive.

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

## <a id="outstanding-27"></a>Outstanding #27 — `/rp/verify-with-data` verified end to end

Shipped and exercised 2026-09-10 on the uat gateway. Only the AS **error
codes** (`40000`–`40500`) remain unseen — they became reachable with this
endpoint but no live request has produced one, which is why #24c asks NDID to
inject them.

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

## <a id="outstanding-30"></a>Outstanding #30 — the first live top-up filed from this build

~~**No live top-up has been filed from this build.**~~ **Resolved
2026-09-16** — `POST /topup` files successfully end to end from here.
⚠ One contract refuses with `501 /
ข้อมูลบางส่วนผิดพลาดไม่สามารถสร้างใบคำขอได้`, and that refusal **reproduces
on the old LandAndHouseWeb app too**, so it is backend-side data on that
contract rather than anything this client sends. Worth raising with the API
team; not a client defect, and not a blocker.

⚠ The `501` above is the one corrected on 2026-09-16: it was first read as a
`product_code` problem and the payload was changed accordingly. That change
stands on its own (it matches the source), but it is **not** the fix — the
refusal is contract-specific backend data and reproduces on LandAndHouseWeb.

## <a id="outstanding-33"></a>Outstanding #33 — the temporary top-up recalculation host

~~**`POST /GetRecalTopupData` is on a temporary test host.**~~
**✅ Resolved 2026-09-14** — the QA endpoint landed as **`POST /topup/recal`
on the mobile API base**, which is exactly what this item asked for: HTTPS,
CORS, and the customer's own bearer token. The top-up flow now calls it
**instead of `GET /topup/detail`**, one response carrying both the limits
and the settlement. See **`POST /topup/recal`**.

Three things remain, none of them blocking:

- ⚠ **Rotate the `…prod` `Basic` account** from the old sample. It shipped
  readable in uat builds 124–126 on 2026-09-13 and is now used by nothing.
- ✅ **The test host is out of the srisawad app** (done 2026-09-14,
  `123cf65` on `pentest_resolved`). Both halves went together:
  `http://34.142.213.42:8080/` from `_kHttpRequestAllowedPrefixes` — the
  only plain-http entry in an otherwise all-https list — and the
  `<domain-config>` block for that IP in `network_security_config.xml`, a
  scoped hole in the pentest's finding-13 cleartext control, which is whole
  again. Removing only the allowlist entry would have left an Android
  cleartext exception for an IP nothing can reach, which is the worse half
  to leave behind.
- ⚠ **The M35 ceiling disagreement is still open** — `/loan/list` grants
  `topup_extra` 5,000 that `/topup/recal` does not recognise, so the
  customer is offered a limit the settlement is not priced at. See
  `TopupFlow.settlementPricingAmount`.

⚠ **The third bullet above is stale.** It was written before the API team
confirmed (also 2026-09-14) that `default_topup_amount` **already includes**
`topup_extra` — so there was never an M35 ceiling disagreement between
`/loan/list` and `/topup/recal`; the client was double-counting the uplift.
`TopupFlow.applySpecialLimit` is now a no-op. See **`POST /topup/recal`** in
CLAUDE.md.

## <a id="topup-redesign"></a>The 2026-09 top-up redesign: provenance, colour rules, reverted experiments

The card and amount screens were rebuilt to a BA design on 2026-09-12, from
`etc/M35 + หน้าจอเติมเงิน_ปิดปรับผ่านแอพมือถือ_หลั.pdf`. ⚠ That PDF is
git-ignored **since 2026-09-13** — the old `/etc/*.txt` rule did not cover it,
so it and three tester screenshots are in the remote's history; see the
`.gitignore` comment.

### The colour rules, all set from device checks on 2026-09-12

Each looked fine in a render and wrong on a phone:

| Element | Treatment | Why |
| --- | --- | --- |
| the two deduction rows (`TopupFigureRow(deduction: true)`) | label, figure **and its `บาท`** in label grey | in value navy a deduction carried the same weight as the payout under it, so the eye found three equal numbers instead of two small ones explaining a large one. The unit joined them on 2026-09-13 — it had stayed navy, leaving the amount screen's two หัก rows half-lit |
| `วงเงินสินเชื่อใหม่สูงสุด` | label grey via `mutedLabel`, figure stays dark | it heads the group whose other rows are muted; opt-in, because the amount screen's `เงินคงเหลือโอนเข้าบัญชี` is also an emphasis row and *is* a conclusion |
| `บาท`, everywhere | the **figure's** colour, not label grey | the unit belongs to the number beside it; a grey unit broke the phrase in half |
| `*เมื่อชำระยอดเพื่อเติมวงเงิน` | orange, not alert red | it qualifies *when* the money arrives rather than warning about anything, and in red beside a payout it read as a problem with the payout |
| the band's ✨ | `#F7BF97` | the one mark on the blue with no warmth |

`TopupPrimaryButton`'s corner radius also went 4 → 12. ⚠ That button is
shared, so it is **the one change that reaches the `_old` pair** — nothing they
*say* changed, but "they render exactly as they did" is approximate rather
than literal.

**ปรับปรุงยอดชำระ is `tonal`, a third variant** (2026-09-13, on request): pale
blue `#E6F4FF` with a `LoanRegisterStyles.value` label, beside the orange
ชำระเงิน. It is a **new flag** rather than a restyled `outlined` precisely
because of the line above — `outlined` is what `topup_amount_page_old.dart`
renders, and editing it in place would move the thing the `_old` pair exists to
be compared against. The same two colours are on the QR screen's copy of this
button, since the two screens hand back and forth.

**A fifth colour was folded out.** A one-off teal caption on the product grid
and the softer `LoanRegisterStyles.required` red both went, because a fifth
colour on one caption read as a different kind of message than it was.
`TopupNotice` gained an optional `accent` for this, so a redesigned screen can
use the design's pure red **without** repainting the un-redesigned steps or the
`_old` pair.

### Experiments that were reverted

- **`+5,000.00` was briefly orange.** The BA's screenshot draws the M35 pair as
  two readings of the same kind, and colouring one of them made the uplift look
  like a separate offer rather than a term of the sum above the bar. The `+` is
  what marks it.
- **The conditions panel briefly sat below the cards**, so the screen would
  open on the offer the way the render does. Reverted on request the same day
  (2026-09-12): it is how a customer finds out *why* a card says what it says,
  which is worth more than leading with the number.
- **The M35 pair was briefly `TopupFigureRow`s.** As table rows the long Thai
  labels squeezed the figures they introduced, and the pair read as entries in
  a list rather than as the arithmetic behind the blue bar. Hence
  `TopupStackedFigure` — set from the BA's screenshot on 2026-09-12.

## <a id="ploan-save-retarget"></a>`POST /ploan`: the two retargets, and what they deleted

The P-Loan save endpoint reached its current shape through two changes, both of
which removed constraints rather than adding them.

**Where it started.** An Extra filed with `POST /topup`, because the FlutterFlow
source it was forked from was a top-up request wearing P-Loan naming. A new
P-Loan filed with `<:8082>/SavePloanContract`, `multipart/form-data`, behind a
baked-in **Basic** service credential (`kPLoanSaveApiAuth`) on a host with its
own port define (`kPLoanSaveApiBase`).

**2026-07-31 — both kinds unified** onto the save endpoint, on instruction. A
P-Loan Extra is a *P-Loan contract that references an existing one*, not a
top-up of it: it draws a separate `topup_extra` line rather than closing the old
loan out, which is also why `payoutAmount` stopped deducting the old principal
on 2026-07-30. `refContractNo` became the only field separating the two kinds.

**2026-08-04 — retargeted to `POST /ploan`** on the mobile API base, with the
customer's own Firebase bearer token. This deleted `kPLoanSaveApiBase` and
`kPLoanSaveApiAuth` from `app_environment.dart` and closed the pentest's
high-severity baked-in-credential finding — a bearer token replaces a shared
secret, so there is nothing left in the bundle to leak. It also removed two
host-side prerequisites that had each needed an app release: the never-built
`httpMultipart` bridge handler, and an `:8082` allowlist entry (Outstanding #2
and #3).

**2026-08-07 — body moved back to `multipart/form-data`** from the JSON the
retarget briefly used. ⚠ Worth understanding why that cost nothing this time:
what made `<:8082>/SavePloanContract` need the native host (verified
2026-07-27) was **never multipart as such** — it was **no CORS headers and a
401'd preflight**, which blocked a browser upload outright and left the bridge
as the only route. `/ploan` sends `access-control-allow-origin: *`, so
`bypassHostBridge: true` uploads with `package:http` directly, in the host and
in a plain browser alike.

**The step-6 payload preview is gone.** A non-prod **ดู/คัดลอก Payload (POST
/ploan)** button used to dump the resolved URL, the form fields, the file parts
and `unresolvedFields` into a copyable dialog; removed 2026-09-07 on request.
`submit_form/`'s own **ดู Payload** button is a different feature and is
untouched. What remains for inspecting a real submit is the failure report,
which only appears when the submit *fails* — so a successful body can no longer
be read off a device. To bring it back, build
`PLoanContractSubmission.fromFlow(flow)` and print `fields` / `files` /
`unresolvedFields`; the mapper is unchanged.

⚠ **A stale caveat was carried until 2026-09-17.** CLAUDE.md kept a note asking
someone to confirm "that `<:7076>/ploan` is reachable and sends
`access-control-allow-origin: *`". Both halves were already answered: the live
submit of 2026-08-17 proved reachability and CORS, and `<:7076>` is the retired
uat gateway — the config has pointed at `srisawad-qa.ecorpgroup.com` since
2026-09-11. Removed.

## <a id="pdfx-leak"></a>`pdfx` 2.9.2 leaks every document the step-6 sheet opens

Found 2026-08-17 while hunting the iOS white screen. It was **not** that bug's
cause, and is a real leak either way.

`PdfController.dispose()` disposes only its `PageController` — it **never calls
`PdfDocument.close()`** — so the pdf.js `PDFDocumentProxy` and its
`ArrayBuffer` stayed alive in the JS heap and the worker for the rest of the
session. Step 6 requires all three contracts to be opened before the NDID row
unlocks, so that left **three** orphaned documents resident from step 6 onward,
through the whole NDID countdown.

`_PdfInlineViewState._release()` now disposes the controller, closes the
document, and clears the global `ImageCache` — `PdfView` rasterises every page
at 2x as a JPEG through `PdfPageImageProvider`, so those bitmaps outlive the
sheet inside a 100 MB budget. Clearing the whole cache is deliberately broad
and cheap: the only other images this app caches are the ID-card/selfie
thumbnails, which re-decode from bytes still held on the flow.

## <a id="step6-summary-rows"></a>Step 6's `สรุปยอดสินเชื่อใหม่`, and which `fee_amount` wins

**Why the section is new-P-Loan only** (hidden for an Extra on request,
2026-07-30). Every row in it was a top-up framing: the reference contract's
headroom (`ยอดจัดสินเชื่อเดิม` / `สินเชื่อวงเงินอเนกประสงค์`, the `topup_extra`
row / `รวมยอดวงเงินที่อนุมัติ`) plus `หักยอดเงินต้นสัญญาเก่า`, the principal a
top-up would clear. A P-Loan Extra draws against none of it — it only
*references* the contract. It took `จำนวนเงินที่จะได้รับ` with it, replaced by
`ยอดโอนเงินเข้าบัญชี` in the next section.

**The duty came from the wrong endpoint for a few hours.** Two endpoints return
a `fee_amount`: `GET /topup/detail` gives the duty on the top-up *total* (**6**
on `MLOAN`/`ฮฮM680702003NF61X` — ฿1 per ฿2,000 of 12,000), while
`POST /topup/calculator` recomputes it for the amount actually requested (**1**
for 2,000). Sourcing it from `/topup/detail` was tried on 2026-07-30 and
reverted the same day: it charged the duty for a larger amount than the
customer is borrowing. Step 2 folds the calculator's in with
`detail.copyWith(feeAmount: plan.feeAmount)`, so `LoanAmountDetail.feeAmount` is
the calculator's from then on.

---

## <a id="loan-detail-debug-dialogs"></a>The two loan-detail debug dialogs, built and removed the same day

**2026-09-22.** Two debug affordances were added to `loan_detail_page.dart`,
one after the other, and **both were removed before the build went to the
tester team**. The screen is byte-for-byte what it was at `1269887`. This is
recorded because the need behind them recurs — *"what did the gateway actually
send?"* and *"what token is this screen calling with?"* are the two questions a
tester report cannot answer — so the next person to want one should know what
was built, and why it is not there.

| Commit | What |
| --- | --- |
| `8cfcaca` | a dialog on page load showing the raw `GET /loan/list` body, with a copy button |
| `020146a` | that reverted in full, replaced by a dialog showing the bearer token, with a copy button |
| `1c88872` | the token dialog removed too — nothing in front of the contract for testers |

**Why the response dialog existed.** Every row on the first two tabs is read
straight off that one response — the screen makes no `loan/detail` call — so
the body answers *"where does this figure come from?"* and *"why is this row
blank?"*, and nothing else on a device does.

Two details worth keeping if it is rebuilt:

- **It captured the body as it came off the wire**, through a new `onResponse`
  hook on `SrisawadApi.send` — the one point where the undecoded body still
  exists, since `send` returns parsed JSON and a failure throws. It was
  deliberately **not** a re-encoding of the parsed `LoanContract`s: a
  reconstruction can only carry the fields this build already reads, which is
  the opposite of what the dialog is opened to find out — a field the API
  added, or one it has stopped sending.
- **The request line had to be masked.** `maskUrlSecrets` covered `hashThaiId`
  but not the mobile API's snake_case `hash_thai_id`, and the copy button puts
  that line into whatever chat the report is pasted into. Widening it meant
  moving it out of `services/external_url.dart` (which imports Flutter and a
  page's styles) into a UI-free file, re-exported so no caller changed. ⚠ **If
  the dialog is rebuilt, that widening has to come back with it** — it went
  away with the revert.

**Why the token dialog replaced it**, then went too. The token is the more
useful half: with it and a contract number, every call the screen makes can be
replayed by hand against the mobile API (which sends
`access-control-allow-origin: *`), which is the only way to separate a payload
problem from a gateway one. Nothing on a device otherwise surfaces it — the
launch `?token=` is gone from `window.location` after the first navigation, and
the live one is resolved per request from the host bridge, so it was resolved
through `AuthToken` and the copy button copied the token **alone**, ready for an
`Authorization` header.

It came out because a dialog demanding dismissal on entry is the first thing a
tester would report, and because a live bearer on screen is a credential on a
clipboard. Both were non-prod-only; neither ever shipped to prod.

**If one is wanted again**, the shape to keep: non-prod-only, opened from the
`(UAT ver…)` tag's diagnostics sheet rather than on page load, so a tester has
to ask for it.
