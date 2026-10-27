#!/usr/bin/env python3
"""Content source for the วงเงินอเนกประสงค์ (P-Loan Extra) user manual.

    python3 scripts/build_docs.py docs/content.py
    bash    scripts/build_pdf.sh  docs/user-manual.html

Scope: the customer-facing path only — the one entry point inside the
ศรีสวัสดิ์ app (the วงเงินอเนกประสงค์ chip on the home loan card), then the
three steps this build actually shows when it is opened from there (จำนวนงวด → ข้อมูลส่วนตัว → สรุป/ยืนยัน).
Steps 1, 2 and 4 of the six-step wizard are skipped on that path by design:
the top-up card already showed the amount, and an existing contract's
collateral is already on file.

Re-shot 2026-08-04 on a real device against live UAT (web build 61/62). That
replaced the browser-on-fixtures captures the first edition used, and it moved
three screens that had only been described in prose — the four addresses, the
documents + NDID block, and the two consents — into images of their own.
Five screens (2.1, 2.7, 2.15, 2.16, 2.17) are still the older captures;
appendix A3 says exactly what differs on them.

2026-10-27 update: the NDID hop gained its agreement screen (2.10), and the
four NDID images (2.10-2.13) were re-captured from the uat web build 223 in
a plain browser - see appendix A8. Section 1.2 (the LandAndHouseWeb top-up
card) was removed: since the 2026-10-14 release the loan card's เติมวงเงิน
opens this build's own top-up card, which does not offer วงเงินอเนกประสงค์.
"""

# --------------------------------------------------------------------- langs
LANGS = [
    ("th", "TH", "ไทย"),
    ("en", "EN", "English"),
]

# ---------------------------------------------------------------------- meta
META = dict(
    title=("คู่มือการใช้งาน วงเงินอเนกประสงค์",
           "Multi-purpose Credit Line — User Manual"),
    brand="ศรีสวัสดิ์ เงินสดทันใจ · วงเงินอเนกประสงค์",
    version="UAT · สินเชื่อเพิ่มจากสัญญาเดิม (P-Loan Extra) · web 61–62 · NDID web 223",
    url="sawad-loan-universal-uat.web.app",
    date="2026-10-27",
    footer="ภาพหน้าจอบันทึกจากเครื่องจริงบนระบบทดสอบ UAT · ข้อมูลที่ระบุตัวบุคคลถูกปิดบัง",

    about_title=("เกี่ยวกับเอกสารนี้", "About this document"),
    contents_title=("สารบัญ", "Contents"),
    issues_title=("ข้อจำกัดของภาพและสิ่งที่ต้องทราบ", "Capture notes and known limits"),

    about=(
        "คู่มือนี้อธิบายการขอ “วงเงินอเนกประสงค์” — การขอสินเชื่อเพิ่มจากสัญญาที่ท่านมีอยู่แล้ว "
        "จัดกลุ่มตามขั้นตอน หมายเลขหลักคือกลุ่ม หมายเลขย่อยคือหน้าจอ "
        "ตัวเลขบนภาพ (1) (2) (3) ตรงกับคำอธิบายใต้ภาพ "
        "ภาพหน้าจอเป็นภาษาไทยตามที่ผู้ใช้เห็นจริง คำอธิบายมีทั้งภาษาไทยและภาษาอังกฤษ "
        "ตัวเลขในภาพมาจากการทดสอบจริงหนึ่งรายการ เป็นเพียงตัวอย่าง ไม่ใช่เงื่อนไขที่เสนอให้ท่าน "
        "ชื่อ เลขบัตรประชาชน เลขที่บัญชี เลขที่สัญญา เบอร์โทรศัพท์ และที่อยู่ ถูกปิดบังไว้ทุกภาพ "
        "รายละเอียดวิธีบันทึกภาพอยู่ในภาคผนวกท้ายเล่ม",
        "This manual covers วงเงินอเนกประสงค์ — borrowing more against a contract you "
        "already hold. It is grouped by stage: the main number is the stage, the "
        "sub-number is a screen. The (1) (2) (3) badges on each image match the notes "
        "below it. Screenshots are in Thai, the language users actually see; the "
        "explanations are given in Thai and English. The figures come from one real "
        "test application — they are an example, not an offer — and every name, ID "
        "number, account number, contract number, phone number and address is masked. "
        "How the images were captured is set out in the appendix.",
    ),

    # The app's own palette (LoanRegisterStyles): orange primary, deep blue values.
    theme=dict(accent="#E8842A", accent_dark="#C96A16",
               accent_soft="#FDF1E5", deep="#1B3A6B"),
)

# -------------------------------------------------------------------- groups
GROUPS = [
    dict(
        num=1, slug="entry",
        title=("เข้าสู่บริการ", "Getting in"),
        intro=(
            "วงเงินอเนกประสงค์เริ่มต้นในแอปศรีสวัสดิ์ จากปุ่ม “วงเงินอเนกประสงค์” บนบัตรสัญญาในหน้าแรก",
            "วงเงินอเนกประสงค์ starts inside the ศรีสวัสดิ์ app, from the วงเงินอเนกประสงค์ "
            "button on a contract card on the home screen.",
        ),
        screens=[
            dict(
                num="1.1", slug="home", img="01-home.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("การ์ดสินเชื่อ (ประเภท / ทะเบียน / ยอดครบกำหนด)",
                     "contract_details.loan_type_name · collateral_information · current_due_amount",
                     "GET /loan/list (แอปมือถือ)"),
                    ("ปุ่ม เติมวงเงิน / วงเงินอเนกประสงค์",
                     "เมนูของ native host app",
                     "เปิด web build นี้ใน WebView (flutter_inappwebview)"),
                    ("โค้ดที่เกี่ยวข้อง",
                     "srisawad_mobile_app — คนละ repo",
                     "ไม่ได้อยู่ใน sawadLoanUniversal"),
                ]),
                title=("หน้าแรกของแอปศรีสวัสดิ์", "The ศรีสวัสดิ์ home screen"),
                items=[
                    (1, "เติมวงเงิน",
                        ("ปุ่มนี้เปิดบริการเติมวงเงิน ซึ่งเป็นคนละบริการ ไม่ได้พาไปยังวงเงินอเนกประสงค์",
                         "opens the top-up service — a different product; it does not lead to "
                         "วงเงินอเนกประสงค์")),
                    (2, "วงเงินอเนกประสงค์",
                        ("ปุ่มในกล่อง “สิทธิพิเศษเฉพาะคุณ” บนบัตรสัญญา กดเพื่อเข้าสู่ขั้นตอนการสมัครทันที",
                         "in the สิทธิพิเศษเฉพาะคุณ box on the contract card — goes straight "
                         "into the application")),
                ],
                note=(
                    "ปุ่มนี้จะปรากฏบนบัตรของสัญญาที่เข้าเงื่อนไขเท่านั้น "
                    "หากสัญญายังไม่เข้าเงื่อนไข หรือมีคำขออยู่แล้ว ระบบจะแจ้งเหตุผลเมื่อกดเข้าไป "
                    "ปุ่ม “วงเงินอเนกประสงค์” นี้เป็นทางเข้าเดียว หน้าจอถัดไปนับเป็นขั้นที่ 2 ของ 4 "
                    "เพราะบัตรสัญญาที่แสดงวงเงินอนุมัติแล้วนับเป็นขั้นที่ 1 "
                    "ปุ่มย้อนกลับในหน้าจอถัดไปจะพาท่านกลับมาที่แอปศรีสวัสดิ์",
                    "The button appears only on a contract that qualifies. If the contract "
                    "is not yet eligible, or already has a request open, the reason is shown "
                    "when you continue. This chip is the only way in. The next screen counts "
                    "as step 2 of 4, since the contract card that shows the approved amount "
                    "is step 1, and Back on it returns you to the ศรีสวัสดิ์ app.",
                ),
            ),
        ],
    ),

    dict(
        num=2, slug="apply",
        title=("ขั้นตอนการขอวงเงิน", "Applying"),
        intro=(
            "สามขั้นตอน คือ เลือกจำนวนงวด → ตรวจสอบข้อมูลส่วนตัว → สรุปและยืนยัน "
            "ระหว่างทางมีการถ่ายรูปยืนยันตัวตน อ่านเอกสารสัญญา และลงนามด้วย NDID",
            "Three steps — pick a term, check your details, then review and confirm. "
            "Along the way you photograph your ID, read the contract documents and sign "
            "with NDID.",
        ),
        screens=[
            dict(
                num="2.1", slug="installment", img="10-installment.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ยอดจัดสินเชื่อใหม่",
                     "PLoanFlow.requestedAmount",
                     "ตัวเลือกมาจาก POST /topup/calculator"),
                    ("จำนวนงวด (36 / 24 / 18 / 12 งวด)",
                     "InstallmentOption.tenor",
                     "$.installments[].tenor"),
                    ("ค่างวด / เดือน",
                     "InstallmentOption.regularPeriodAmt",
                     "$.installments[].regular_period_amt"),
                    ("ค่าอากรแสตมป์ (ใช้คำนวณต่อ)",
                     "InstallmentPlan.feeAmount",
                     "$.fee_amount"),
                    ("แถบขั้นตอน 1–4",
                     "PLoanFlow.visitedSteps",
                     "สถานะในแอป ไม่มี API"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_installment_page.dart"),
                ]),
                title=("เลือกจำนวนงวด (ขั้นที่ 2)", "Pick a term (step 2)"),
                items=[
                    (1, "ยอดจัดวงเงินอเนกประสงค์",
                        ("ยอดที่จะจัดสินเชื่อ มาจากวงเงินเพิ่มพิเศษที่อนุมัติในหน้าก่อนหน้า "
                         "แก้ไขที่หน้านี้ไม่ได้",
                         "the amount being financed, carried over from the special offer on "
                         "the previous screen; it cannot be changed here")),
                    (2, None,
                        ("เลือกจำนวนงวดหนึ่งรายการ ตัวเลขด้านขวาคือค่างวดต่อเดือนของงวดนั้น "
                         "ยิ่งจำนวนงวดมาก ค่างวดต่อเดือนยิ่งน้อย",
                         "choose one term; the figure on the right is the monthly payment for "
                         "it — a longer term means a smaller monthly payment")),
                    (3, "ยืนยัน",
                        ("กดได้เมื่อเลือกจำนวนงวดแล้ว ปุ่มจะเป็นสีเทาจนกว่าจะเลือก",
                         "becomes active once a term is selected; it stays pale until then")),
                ],
                note=(
                    "ภาพนี้บันทึกจากบิลด์รุ่นก่อน หัวข้อยอดเงินจึงเขียนว่า “ยอดจัดสินเชื่อใหม่” "
                    "ปัจจุบันหน้าจอนี้เขียนว่า “ยอดจัดวงเงินอเนกประสงค์” ตำแหน่งและวิธีใช้เหมือนเดิม",
                    "This image is from an earlier build, where the amount was headed "
                    "ยอดจัดสินเชื่อใหม่. The current app reads ยอดจัดวงเงินอเนกประสงค์ in the "
                    "same place; nothing else about the screen changed.",
                ),
            ),
            dict(
                num="2.2", slug="customer-data", img="20-customer-data.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ธนาคาร (ชื่อ / โลโก้)",
                     "PLoanFlow.bankCode",
                     "GET /loan/list $.contract_bank_brandname"),
                    ("เลขที่บัญชี",
                     "PLoanFlow.bankAccountNo",
                     "$.contract_bank_account"),
                    ("ชื่อ-สกุล",
                     "CustomerDetail.title + firstName + lastName",
                     "GET /user/detail $.title / $.first_name / $.last_name"),
                    ("เบอร์โทรศัพท์",
                     "CustomerDetail.phoneNumber",
                     "$.phone_number"),
                    ("ที่อยู่ปัจจุบัน (ย่อ)",
                     "CustomerAddressBook.currentAddress",
                     "GET /profile/address/{hashThaiId} $.current_address"),
                    ("ปุ่ม ไม่ถูกต้อง / ยืนยัน",
                     "ด่านตรวจใน PLoanFlow",
                     "ไม่มี API"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_customer_data_page.dart"),
                ]),
                title=("ตรวจสอบข้อมูลส่วนตัว (ขั้นที่ 3)", "Check your details (step 3)"),
                items=[
                    (1, "ข้อมูลเลขที่บัญชี",
                        ("บัญชีที่จะรับเงิน ดึงมาจากสัญญาเดิมของท่าน",
                         "the account the money goes to, taken from your existing contract")),
                    (2, "ชื่อ-สกุล / เบอร์โทรศัพท์",
                        ("ชื่อเจ้าของสัญญา และเบอร์ที่ใช้ติดต่อและรับ SMS เกี่ยวกับคำขอนี้",
                         "the account holder's name, and the number used to contact you "
                         "about this request")),
                    (3, "ไม่ถูกต้อง / ยืนยัน",
                        ("กด “ยืนยัน” หากข้อมูลถูกต้องทั้งหมด "
                         "หากไม่ถูกต้อง กด “ไม่ถูกต้อง” แล้วติดต่อสาขาเพื่อแก้ไขก่อนสมัคร",
                         "tap ยืนยัน if everything is right; if not, tap ไม่ถูกต้อง and have "
                         "a branch correct it before applying")),
                ],
                note=(
                    "เลื่อนหน้าจอลงเพื่อดูที่อยู่ทั้งสี่รายการ ดูหน้าถัดไป",
                    "Scroll down for all four addresses — see the next screen.",
                ),
            ),
            dict(
                num="2.3", slug="addresses", img="21-addresses.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ที่อยู่ปัจจุบัน",
                     "CustomerAddressBook.currentAddress",
                     "GET /profile/address/{hashThaiId} $.current_address"),
                    ("ที่อยู่ตามทะเบียนบ้าน",
                     "CustomerAddressBook.registrationAddress",
                     "$.registration_address"),
                    ("ที่อยู่ตามบัตรประชาชน",
                     "CustomerAddressBook.idCardAddress",
                     "$.id_card_address"),
                    ("ที่ทำงาน/ที่อยู่อื่นๆ",
                     "CustomerAddressBook.otherAddress",
                     "$.other_address"),
                    ("โครงสร้างของแต่ละที่อยู่",
                     "AddressInfo.addressDetails / subDistrict / district / province / postalCode",
                     "$.address_details · $.address_sub_district · $.address_district · $.address_province · $.address_postal_code"),
                    ("โมเดล / Model",
                     "lib/models/customer_address.dart",
                     "UserApi.fetchAddressBook()"),
                ]),
                title=("ที่อยู่ทั้งสี่รายการ", "Your four addresses"),
                items=[
                    (1, "ที่อยู่ปัจจุบัน",
                        ("ที่อยู่ที่ท่านพักอาศัยจริงในปัจจุบัน",
                         "where you actually live now")),
                    (2, "ที่อยู่ตามทะเบียนบ้าน / ที่อยู่ตามบัตรประชาชน",
                        ("ที่อยู่ตามเอกสารราชการ ทั้งสองรายการอาจซ้ำกับที่อยู่ปัจจุบันได้",
                         "the addresses on your official records; either may repeat the "
                         "current one")),
                    (3, "ที่ทำงาน/ที่อยู่อื่นๆ",
                        ("ที่อยู่ที่ทำงาน หรือที่อยู่สำรองที่เคยแจ้งไว้",
                         "your workplace, or any other address on file")),
                ],
                note=(
                    "ที่อยู่ทั้งสี่รายการแก้ไขในแอปไม่ได้ หากรายการใดไม่ถูกต้อง "
                    "กด “ไม่ถูกต้อง” ที่ด้านล่าง แล้วติดต่อสาขาเจ้าของบัญชีเพื่อแก้ไขก่อนสมัคร "
                    "ช่องที่ไม่มีข้อมูลจะแสดงเป็นช่องว่าง ไม่ถือว่าผิดพลาด",
                    "None of the four can be edited in the app. If one is wrong, tap "
                    "ไม่ถูกต้อง at the bottom and have the branch that owns your account fix "
                    "it before you apply. An address the branch has never recorded simply "
                    "shows blank — that is not an error.",
                ),
            ),
            dict(
                num="2.4", slug="confirm-account", img="25-confirm-account.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ธนาคารในแผ่นยืนยัน",
                     "PLoanFlow.bankCode",
                     "GET /loan/list $.contract_bank_brandname"),
                    ("เลขที่บัญชีในแผ่นยืนยัน",
                     "PLoanFlow.bankAccountNo",
                     "$.contract_bank_account"),
                    ("ปุ่ม ยืนยัน",
                     "ผูกบัญชีนี้กับคำขอ",
                     "ส่งไปพร้อม POST /ploan"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_customer_data_page.dart"),
                ]),
                title=("ยืนยันบัญชีรับเงิน", "Confirm the receiving account"),
                items=[
                    (1, None,
                        ("ตรวจชื่อธนาคารและเลขที่บัญชีอีกครั้ง เงินจะโอนเข้าบัญชีนี้",
                         "check the bank and account number once more — this is where the "
                         "money is sent")),
                    (2, "ยืนยัน",
                        ("กดเพื่อไปยังหน้าสรุป หรือกด “ตรวจสอบอีกครั้ง” เพื่อกลับไปดูข้อมูล",
                         "continues to the summary; ตรวจสอบอีกครั้ง goes back to the details")),
                ],
            ),
            dict(
                num="2.5", slug="summary", img="30-summary.png",
                title=("สรุปรายละเอียดของสัญญา (ขั้นที่ 4)", "Contract summary (step 4)"),
                items=[
                    (1, "ยอดจัดวงเงินอเนกประสงค์ / ค่าอากรแสตมป์",
                        ("ยอดที่จัดให้เต็มจำนวน และค่าอากรแสตมป์ตามกฎหมายที่หักจากยอดนั้น",
                         "the full amount financed, and the statutory stamp duty deducted "
                         "from it")),
                    (2, None,
                        ("ค่างวด จำนวนงวด อัตราดอกเบี้ยต่อเดือน และวันที่ต้องชำระของสัญญาใหม่ "
                         "ใต้บรรทัดดอกเบี้ยคือเลขที่สัญญาเดิมที่ใช้อ้างอิง",
                         "the monthly payment, term, monthly interest rate and payment day of "
                         "the new contract; under the interest line is the existing contract "
                         "it references")),
                    (3, "ยอดโอนเงินเข้าบัญชี",
                        ("ยอดที่จะโอนเข้าบัญชีของท่าน คือ ยอดจัดวงเงินอเนกประสงค์ ลบ ค่าอากรแสตมป์",
                         "what is paid into your account: the amount financed minus the "
                         "stamp duty")),
                ],
                note=(
                    "หน้านี้ยาว ต้องเลื่อนลงไปทำอีกสามอย่างให้ครบก่อนจึงจะกดยืนยันได้ "
                    "คือ ถ่ายรูปยืนยันตัวตน อ่านและยอมรับเอกสารสัญญา และลงนามด้วย NDID",
                    "This screen is long. Three more things further down must be completed "
                    "before you can confirm: the identity photos, accepting the contract "
                    "documents, and signing with NDID.",
                ),
                defs=("รายการยอดเงินบนหน้าสรุป · การเชื่อมโยงข้อมูล (model / API)", "The figures on the summary · Data mapping (model / API)", [
                    ("↓ การเชื่อมโยงข้อมูล / Data mapping",
                     "model / struct",
                     "API + JSON key"),
                    ("ยอดจัดวงเงินอเนกประสงค์",
                     "ยอดที่จัดให้ในสัญญาใหม่ เต็มจำนวน",
                     "the full amount financed under the new contract"),
                    ("ค่าอากรแสตมป์",
                     "ค่าอากรตามกฎหมาย คิดจากยอดที่ท่านขอจริง",
                     "the statutory duty, calculated on the amount you actually requested"),
                    ("ค่างวด",
                     "ยอดที่ต้องชำระในแต่ละงวด",
                     "what you pay each month"),
                    ("ชำระทุกวันที่",
                     "วันที่ของทุกเดือนที่ต้องชำระค่างวด",
                     "the day of the month the payment falls due"),
                    ("ยอดโอนเงินเข้าบัญชี",
                     "ยอดจัดวงเงินอเนกประสงค์ ลบ ค่าอากรแสตมป์",
                     "the amount financed minus the stamp duty"),
                    ("ยอดจัดวงเงินอเนกประสงค์",
                     "PLoanFlow.requestedAmount",
                     "ส่งเป็น payload loan_amount"),
                    ("ค่าอากรแสตมป์",
                     "LoanAmountDetail.feeAmount",
                     "GET /topup/detail $.fee_amount"),
                    ("ค่างวด",
                     "InstallmentOption.regularPeriodAmt",
                     "POST /topup/calculator $.installments[].regular_period_amt"),
                    ("จำนวนงวด",
                     "InstallmentOption.tenor",
                     "$.installments[].tenor"),
                    ("ดอกเบี้ย (ต่อเดือน)",
                     "LoanAmountDetail.interestRate",
                     "GET /topup/detail $.interest_rate"),
                    ("เลขที่สัญญา",
                     "LoanAmountDetail.contractNo",
                     "$.contract_no"),
                    ("ชำระทุกวันที่",
                     "LoanAmountDetail.dueDay",
                     "$.due_day"),
                    ("ยอดโอนเงินเข้าบัญชี",
                     "PLoanFlow.payoutAmount = requestedAmount − detail.feeAmount",
                     "ส่งเป็น payload transfer_amount"),
                    ("ข้อมูลเลขที่บัญชี",
                     "PLoanFlow.bankAccountNo / bankCode",
                     "GET /loan/list"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_conclusion_page.dart"),
                ]),
            ),
            dict(
                num="2.6", slug="identity-empty", img="31-identity-empty.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("บังคับถ่ายรูปภาพบัตรประชาชน",
                     "payload key customer_image_2",
                     "POST /ploan (multipart file part)"),
                    ("บังคับถ่ายรูปภาพตนเองคู่กับบัตรประชาชน",
                     "payload key customer_image_3",
                     "POST /ploan (multipart file part)"),
                    ("การตรวจเลขบัตรประชาชน",
                     "PLoanApi.validateThaiId()",
                     "POST /vision/thai-id-validate"),
                    ("เอกสารประกอบสัญญา (หัวข้อ)",
                     "LoanDocuments",
                     "POST /pdf/loan"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_conclusion_page.dart"),
                ]),
                title=("ถ่ายรูปยืนยันตัวตน", "The identity photos"),
                items=[
                    (1, "บังคับถ่ายรูปภาพบัตรประชาชน",
                        ("ถ่ายรูปบัตรประชาชนของท่านเอง ระบบตรวจเลขบัตรให้ตรงกับเจ้าของสัญญา "
                         "และตรวจว่าบัตรยังไม่หมดอายุ",
                         "photograph your own ID card; the number is checked against the "
                         "account holder and the card must not be expired")),
                    (2, "บังคับถ่ายรูปภาพตนเองคู่กับบัตรประชาชน",
                        ("ถ่ายรูปตนเองพร้อมถือบัตรประชาชนให้เห็นหน้าและบัตรชัดเจน",
                         "photograph yourself holding the ID card, with both your face and "
                         "the card clearly visible")),
                    (3, "เอกสารประกอบสัญญา",
                        ("ถัดลงมาคือเอกสารสัญญาสามฉบับ ที่ต้องเปิดอ่านและกดยอมรับ",
                         "below them are the three contract documents you must open and "
                         "accept")),
                ],
                note=(
                    "ทั้งสองรูปเป็นข้อบังคับ กล้องจะเปิดจากในแอปศรีสวัสดิ์ พร้อมกรอบช่วยจัดตำแหน่ง "
                    "ถ่ายในที่มีแสงพอ ให้เห็นตัวอักษรบนบัตรครบทุกบรรทัด",
                    "Both photos are required. The camera opens from inside the ศรีสวัสดิ์ "
                    "app with a framing guide. Shoot in good light and make sure every line "
                    "of text on the card is readable.",
                ),
            ),
            dict(
                num="2.7", slug="identity-done", img="35-identity-done.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("รูปบัตรประชาชนที่แนบแล้ว",
                     "payload key customer_image_2",
                     "POST /ploan (multipart file part)"),
                    ("รูปตนเองคู่บัตรที่แนบแล้ว",
                     "payload key customer_image_3",
                     "POST /ploan (multipart file part)"),
                    ("ผลตรวจเลขบัตรประชาชน",
                     "PLoanApi.validateThaiId()",
                     "POST /vision/thai-id-validate"),
                    ("ปุ่มกากบาทลบรูป",
                     "ล้าง photo slot ใน PLoanFlow",
                     "ไม่มี API"),
                ]),
                title=("เมื่อแนบรูปแล้ว", "Once the photos are attached"),
                items=[
                    (1, None,
                        ("รูปบัตรประชาชนที่แนบแล้วจะแสดงเป็นภาพตัวอย่าง",
                         "the attached ID-card photo is shown as a thumbnail")),
                    (2, None,
                        ("รูปตนเองคู่กับบัตรประชาชนที่แนบแล้ว",
                         "the attached selfie-with-ID photo")),
                    (3, None,
                        ("กดกากบาทเพื่อลบรูปและถ่ายใหม่",
                         "tap the cross to delete a photo and retake it")),
                ],
                note=(
                    "รูปในภาพตัวอย่างเป็นภาพสมมติที่สร้างขึ้นเพื่อทำคู่มือ ไม่ใช่บัตรจริงของผู้ใด "
                    "หากระบบอ่านเลขบัตรไม่ได้ หรือเลขบัตรไม่ตรงกับเจ้าของสัญญา จะให้ถ่ายใหม่",
                    "The images in the sample are synthetic stand-ins made for this manual, "
                    "not anyone's real card. If the number cannot be read, or does not match "
                    "the account holder, you are asked to retake the photo.",
                ),
            ),
            dict(
                num="2.8", slug="documents-ndid", img="32-documents-ndid.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ใบคำขอสินเชื่อใหม่",
                     "LoanDocuments.request",
                     "POST /pdf/loan $.request"),
                    ("ใบรับเงิน",
                     "LoanDocuments.receipt",
                     "$.receipt"),
                    ("เอกสารสัญญา",
                     "LoanDocuments.agreement",
                     "$.agreement"),
                    ("ไฟล์ที่ส่งตอนยืนยัน",
                     "topup_request_file / topup_receipt_file / topup_argeement_file",
                     "POST /ploan (multipart file parts)"),
                    ("ลงนามเอกสารและยืนยันตัวตน NDID",
                     "เปิด ndid_terms_page → ndid_bank_select_page → ndid_verify_page",
                     "POST /idp/list · POST /rp/verify-with-data"),
                    ("ความยินยอม",
                     "marketing_consent / sensitive_consent",
                     "POST /ploan"),
                ]),
                title=("เอกสารประกอบสัญญาและการลงนาม", "The documents, and signing them"),
                items=[
                    (1, "เอกสารประกอบสัญญา",
                        ("สามฉบับ คือ ใบคำขอสินเชื่อใหม่ ใบรับเงิน และเอกสารสัญญา "
                         "กดทีละฉบับเพื่อเปิดอ่านและกดยอมรับ",
                         "three of them — the loan request form, the receipt and the "
                         "contract. Tap each one to read it and accept it")),
                    (2, "ลงนามเอกสารและยืนยันตัวตน NDID",
                        ("กดเพื่อเริ่มลงนามด้วย NDID แทนการเซ็นชื่อ เริ่มจากหน้าข้อตกลง NDID (2.10)",
                         "starts NDID signing, which replaces a written signature — it opens "
                         "on the NDID agreement (2.10)")),
                    (3, "ความยินยอม",
                        ("ช่องยินยอมสองข้อ อยู่ถัดลงไปอีกเล็กน้อย",
                         "the two consent boxes, a little further down")),
                ],
                note=(
                    "ต้องยอมรับเอกสารครบทั้งสามฉบับก่อน จึงจะกดลงนาม NDID ได้ "
                    "หากกดก่อน ระบบจะแจ้งให้อ่านเอกสารให้ครบ — อ่านก่อน แล้วจึงลงนาม",
                    "All three documents must be accepted before NDID signing will open. "
                    "Tapping it early tells you what is still missing — read first, then "
                    "sign.",
                ),
            ),
            dict(
                num="2.9", slug="document-view", img="33-document-view.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("เนื้อหาเอกสารที่แสดง",
                     "LoanDocuments.request / receipt / agreement (base64 PDF)",
                     "POST /pdf/loan"),
                    ("ปุ่ม ยอมรับ",
                     "ตั้งสถานะยอมรับใน PLoanFlow",
                     "ปลดล็อกปุ่มยืนยันในหน้าสรุป"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "pdf_view.dart"),
                ]),
                title=("อ่านและยอมรับเอกสาร", "Read and accept a document"),
                items=[
                    (1, None,
                        ("เอกสารฉบับจริงแสดงในหน้าจอนี้ เลื่อนเพื่ออ่านทั้งฉบับ",
                         "the real document is rendered here; scroll to read all of it")),
                    (2, None,
                        ("ติ๊กช่องเพื่อรับรองว่าได้อ่านและยอมรับเอกสารฉบับนี้",
                         "tick the box to confirm you have read and accept this document")),
                    (3, "ยอมรับ",
                        ("กดเพื่อบันทึกการยอมรับ แล้วทำซ้ำกับเอกสารที่เหลือ",
                         "records your acceptance; repeat for the remaining documents")),
                ],
                note=(
                    "เอกสารอ่านได้ในแอปเท่านั้น ไม่มีปุ่มดาวน์โหลดและไม่มีปุ่มเปิดในแท็บใหม่ "
                    "หากต้องการสำเนาเอกสารสัญญา ติดต่อสาขาเจ้าของบัญชี หรือโทร 1652",
                    "The document is readable in the app only — there is no download button "
                    "and no open-in-a-new-tab button. For a copy of the contract, contact "
                    "the branch that owns your account, or call 1652.",
                ),
            ),
            dict(
                num="2.10", slug="ndid-terms", img="39-ndid-terms.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ข้อตกลงการใช้บริการ",
                     "kNdidTermsClauses (ndid_terms_content.dart)",
                     "ข้อความคงที่ ตามข้อตกลงขั้นต่ำของ NDID — ไม่มี API"),
                    ("ปุ่ม ปฏิเสธ",
                     "Diagnostics.log('ndid terms declined')",
                     "บันทึกเฉพาะในเครื่อง ไม่มี API"),
                    ("ปุ่ม ยอมรับ",
                     "เปิดหน้าเลือกผู้ให้บริการ (2.11)",
                     "ไม่มี API"),
                    ("หน้าจอ / Screen",
                     "lib/loan_register/",
                     "ndid_terms_page.dart"),
                ]),
                title=("เงื่อนไขและข้อตกลง NDID", "The NDID agreement"),
                items=[
                    (1, "ข้อตกลงในการใช้บริการพิสูจน์และยืนยันตัวตน",
                        ("ข้อตกลงการใช้บริการ NDID ข้อ 1–9 เลื่อนอ่านได้ในหน้าเดียว",
                         "the NDID service agreement, clauses 1–9, read as one scroll")),
                    (2, "ปฏิเสธ",
                        ("กดเพื่อไม่ยอมรับ ระบบจะกลับไปหน้าสรุป และยังลงนาม NDID ไม่ได้",
                         "declines — you return to the summary, and NDID signing stays "
                         "incomplete")),
                    (3, "ยอมรับ",
                        ("กดเพื่อยอมรับข้อตกลง แล้วไปเลือกผู้ให้บริการยืนยันตัวตน",
                         "accepts the agreement and moves on to choosing your provider")),
                ],
                note=(
                    "หน้านี้จะแสดงทุกครั้งที่เริ่มยืนยันตัวตน NDID เพราะการยินยอมเป็นรายครั้ง "
                    "ระบบไม่จำคำตอบจากครั้งก่อน",
                    "This screen appears every time NDID signing starts — consent is given "
                    "per verification, so an earlier answer is not remembered.",
                ),
            ),
            dict(
                num="2.11", slug="ndid-banks", img="40-ndid-banks.png",
                title=("เลือกผู้ให้บริการยืนยันตัวตน NDID", "Choose your NDID provider"),
                items=[
                    (1, "ผู้ให้บริการที่เคยลงทะเบียน NDID",
                        ("ธนาคารหรือผู้ให้บริการที่ท่านลงทะเบียน NDID ไว้แล้ว "
                         "เลือกจากกลุ่มนี้เพื่อยืนยันตัวตนได้ทันที",
                         "banks or providers you have already registered with for NDID — "
                         "pick one here to verify straight away")),
                    (2, "ผู้ให้บริการที่ยังไม่ลงทะเบียน NDID",
                        ("เลือกได้เช่นกัน แต่ต้องลงทะเบียน NDID ในแอปของธนาคารนั้นก่อน "
                         "จึงจะยืนยันตัวตนได้ (มีข้อความแจ้งใต้กลุ่มนี้)",
                         "can be picked too, but you must register for NDID in that bank's app "
                         "before it can verify you (a note under the group says so)")),
                    (3, "ถัดไป",
                        ("กดได้เมื่อเลือกแล้ว (กรอบสีส้ม) เพื่อส่งคำขอยืนยันตัวตน",
                         "enabled once one is selected (orange outline); sends the "
                         "verification request")),
                ],
                note=(
                    "หากกลุ่มบนว่างเปล่า แปลว่าท่านยังไม่ได้ลงทะเบียน NDID กับที่ใดเลย "
                    "เลือกธนาคารที่ท่านเป็นลูกค้าจากกลุ่มล่าง แล้วลงทะเบียนในแอปธนาคารระหว่างยืนยันตัวตน "
                    "ในแอปจริงรายชื่อและโลโก้ดึงมาจากระบบ NDID ภาพนี้บันทึกจากเบราว์เซอร์ "
                    "จึงแสดงรายชื่อธนาคารตัวอย่าง (ดูภาคผนวก A8)",
                    "An empty top group means you have not registered for NDID anywhere yet: "
                    "pick a bank you hold an account with from the lower group, and register "
                    "in its app as part of verifying. In the app the names and logos come live "
                    "from NDID; this image was captured in a browser, so it shows sample banks "
                    "(see appendix A8).",
                ),
                defs=("NDID · การเชื่อมโยงข้อมูล (model / API)", "NDID · Data mapping (model / API)", [
                    ("NDID",
                     "บริการยืนยันตัวตนดิจิทัลผ่านธนาคารที่ท่านเป็นลูกค้า "
                     "ใช้ลงนามเอกสารสัญญาแทนการเซ็นชื่อ",
                     "digital identity verification through a bank you already bank with, "
                     "used here to sign the contract instead of a written signature"),
                    ("↓ การเชื่อมโยงข้อมูล / Data mapping",
                     "model / struct",
                     "API + JSON key"),
                    ("รายชื่อผู้ให้บริการ (IdP)",
                     "NdidApi.listIdps() — กลุ่มบนส่งเลขบัตรประชาชนไปด้วย",
                     "POST {ndid_url_base}/idp/list (IAL 2.3 / AAL 2.2)"),
                    ("ชื่อและโลโก้ธนาคารในรายการ",
                     "NdidIdp.logoUrl — โลโก้สูงสุด 4 ช่องในกลุ่มบน ช่องอื่นแสดงอักษรย่อ",
                     "$.logo_url / $.has_logo จาก /idp/list"),
                    ("ปุ่ม ถัดไป",
                     "บันทึก ndidIdpId / ndidIdpName แล้วเปิดหน้ายืนยันตัวตน",
                     "ไม่มี API (คำขอสร้างในหน้าถัดไป)"),
                    ("ค่า base URL",
                     "AppConfig api_url.ndid_url_base (Firestore)",
                     "uat: https://uat.ndid.srisawadpower.com"),
                    ("หน้าจอ / Screen",
                     "lib/loan_register/",
                     "ndid_bank_select_page.dart"),
                ]),
            ),
            dict(
                num="2.12", slug="ndid-waiting", img="42-ndid-waiting.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("สร้างคำขอยืนยันตัวตน",
                     "NdidApi.createVerifyRequest() — หมดเวลา 1 ชั่วโมง",
                     "POST /rp/verify-with-data (ถ้าไม่พบ AS ใช้ POST /rp/verify)"),
                    ("Transaction Ref",
                     "NdidVerifyRequest.transactionRef",
                     "$.transaction_ref (ตัวเลข 5–9 หลัก สร้างโดย gateway)"),
                    ("สถานะการยืนยัน",
                     "NdidApi.getVerifyStatus() — ทุก 3 วิ ใน 30 วิแรก แล้วทุก 15 วิ",
                     "GET /rp/verify/{reference_id}"),
                    ("อ้างอิงคำขอ NDID",
                     "payload key ndid_reference_id",
                     "POST /ploan"),
                    ("ปุ่ม ตรวจสอบสถานะ",
                     "เรียก poll สถานะซ้ำ",
                     "NDID status"),
                    ("ปุ่ม ยกเลิก",
                     "NdidApi.closeVerifyRequest() แล้วกลับหน้าสรุป",
                     "ปิดคำขอแบบ best-effort"),
                    ("หน้าจอ / Screen",
                     "lib/loan_register/",
                     "ndid_verify_page.dart"),
                ]),
                title=("รอยืนยันตัวตนในแอปธนาคาร", "Waiting for the bank app"),
                items=[
                    (1, None,
                        ("เวลาที่เหลือสำหรับทำรายการ ต้องยืนยันในแอปธนาคารภายในเวลานี้ "
                         "ทำได้ครั้งเดียวต่อหนึ่งรายการ",
                         "the time left to finish; verify in the bank's app before it runs "
                         "out — one attempt per request")),
                    (2, "ตรวจสอบสถานะ",
                        ("ในแอปจริง ตำแหน่งนี้คือปุ่ม “ตรวจสอบสถานะ” กดเพื่อถามผลจากระบบทันที "
                         "ปุ่มสีส้มในภาพ “จำลองยืนยันตัวตนสำเร็จ” มีเฉพาะในเบราว์เซอร์ ลูกค้าไม่เห็น",
                         "in the app this is ตรวจสอบสถานะ, which asks for the result right away. "
                         "The orange จำลองยืนยันตัวตนสำเร็จ button in this image exists only in a "
                         "browser — customers never see it")),
                    (3, "ยกเลิก",
                        ("กดเพื่อยกเลิกคำขอยืนยันตัวตนนี้",
                         "cancels this verification request")),
                ],
                note=(
                    "ขั้นตอนนี้ทำในแอปของธนาคารที่ท่านเลือก ไม่ใช่ในหน้าจอนี้ "
                    "ข้อความบนหน้าจอเป็นข้อความมาตรฐานของ NDID: ไปยืนยันตัวตนในแอปของผู้ให้บริการภายใน 60 นาที "
                    "แล้วกลับมาทำรายการต่อที่นี่ หน้าจอจะตรวจผลให้ทันทีที่กลับมา "
                    "Transaction Ref เป็นตัวเลขไม่เกิน 9 หลัก และเป็นเลขเดียวกับที่แอปธนาคารแสดง "
                    "(ภาพนี้จากเบราว์เซอร์จึงแสดง 000000001)",
                    "This step happens in your bank's own app, not on this screen. The text "
                    "is NDID's standard message: verify in the provider's app within 60 "
                    "minutes, then come back here — the screen checks as soon as you return. "
                    "The Transaction Ref is a number of up to 9 digits, and your bank app "
                    "shows the same one (this browser capture shows 000000001).",
                ),
            ),
            dict(
                num="2.13", slug="ndid-done", img="43-ndid-done.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ผลยืนยันตัวตน",
                     "NdidSubject (lib/models/ndid_subject.dart)",
                     "จากสถานะของ NDID"),
                    ("อ้างอิงคำขอ NDID",
                     "ndid_reference_id",
                     "ส่งต่อไปกับ POST /ploan"),
                    ("ปุ่ม ตกลง",
                     "กลับไปหน้าสรุป",
                     "ไม่มี API"),
                ]),
                title=("ยืนยันตัวตนสำเร็จ", "Verification succeeded"),
                items=[
                    (1, None,
                        ("ข้อความยืนยันว่าธนาคารตอบรับการยืนยันตัวตนแล้ว",
                         "confirms the bank accepted the verification")),
                    (2, "ตกลง",
                        ("กดเพื่อกลับไปยังหน้าสรุป",
                         "returns you to the summary screen")),
                ],
                note=(
                    "หากธนาคารปฏิเสธ หมดเวลา หรือท่านยกเลิกในแอปธนาคาร หน้ายืนยันตัวตนจะแสดงข้อความสีแดง "
                    "ตามข้อความมาตรฐานของ NDID เช่น “ท่านไม่สามารถทำรายการได้ในขณะนี้ "
                    "กรุณาทำรายการใหม่หรือเลือกผู้ให้บริการยืนยันตัวตนรายอื่น” และมีปุ่ม “ลองใหม่”",
                    "If the bank rejects it, the request times out, or you cancel in the bank "
                    "app, the verify screen shows a red message in NDID's standard wording — "
                    "e.g. ท่านไม่สามารถทำรายการได้ในขณะนี้ กรุณาทำรายการใหม่หรือเลือกผู้ให้บริการ"
                    "ยืนยันตัวตนรายอื่น — with a ลองใหม่ (retry) button.",
                ),
            ),
            dict(
                num="2.14", slug="consents", img="36-consents.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ยินยอมการตลาด",
                     "payload key marketing_consent",
                     "POST /ploan"),
                    ("ยินยอมข้อมูลอ่อนไหว",
                     "payload key sensitive_consent",
                     "POST /ploan"),
                    ("ข้อความบอกเหตุที่ปุ่มยังกดไม่ได้",
                     "PLoanSubmission.unresolvedFields",
                     "p_loan_submission.dart"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_conclusion_page.dart"),
                ]),
                title=("ความยินยอม และเหตุที่ปุ่มยืนยันยังกดไม่ได้",
                       "The consents, and why ยืนยัน is still off"),
                items=[
                    (1, "ยินยอมการตลาด / ยินยอมข้อมูลอ่อนไหว",
                        ("“ยินยอมข้อมูลอ่อนไหว” มีดอกจันสีแดง เป็นข้อบังคับ ต้องติ๊กจึงจะยืนยันได้ "
                         "ส่วน “ยินยอมการตลาด” เลือกได้ตามความสมัครใจ ไม่ติ๊กก็สมัครได้",
                         "ยินยอมข้อมูลอ่อนไหว carries a red asterisk and is required — it must "
                         "be ticked. ยินยอมการตลาด is genuinely optional and blocks nothing")),
                    (2, None,
                        ("ข้อความสีแดงเหนือปุ่มบอกว่ายังขาดอะไร ในภาพนี้คือยังไม่ได้ถ่ายรูปบัตรประชาชน "
                         "ทำสิ่งที่ขาดให้ครบ ข้อความจะหายไปและปุ่มจะกดได้",
                         "the red line above the button names what is still missing — here, "
                         "the ID-card photo. Finish it and the line disappears and the button "
                         "becomes tappable")),
                ],
                note=(
                    "การไม่ติ๊ก “ยินยอมการตลาด” เป็นคำตอบที่ระบบบันทึกจริง ไม่ใช่การข้าม "
                    "ท่านจะไม่ถูกติดต่อเพื่อเสนอผลิตภัณฑ์",
                    "Leaving ยินยอมการตลาด unticked is recorded as a real answer, not skipped "
                    "— you will not be contacted with product offers.",
                ),
            ),
            dict(
                num="2.15", slug="ready", img="34-ready-to-submit.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("รายการที่ยังขาด",
                     "PLoanSubmission.unresolvedFields",
                     "ตรวจในเครื่องก่อนเปิดปุ่มยืนยัน"),
                    ("ฟิลด์ข้อความที่จะส่ง",
                     "PLoanSubmission.fields",
                     "POST /ploan (multipart/form-data)"),
                    ("ไฟล์ที่จะส่ง",
                     "PLoanSubmission.files (PLoanFilePart)",
                     "POST /ploan — 5 file parts"),
                    ("พิกัดที่แนบไปกับคำขอ",
                     "payload latitude / longitude",
                     "POST /ploan"),
                ]),
                title=("ตรวจความพร้อมก่อนยืนยัน", "Ready to confirm"),
                items=[
                    (1, None,
                        ("เอกสารทั้งสามฉบับต้องขึ้น “ยอมรับแล้ว”",
                         "all three documents must read ยอมรับแล้ว")),
                    (2, None,
                        ("ช่อง NDID ต้องขึ้น “ยืนยันแล้ว” พร้อมเครื่องหมายถูกสีเขียว",
                         "the NDID row must read ยืนยันแล้ว with a green tick")),
                    (3, "ความยินยอม",
                        ("ช่อง “ยินยอมข้อมูลอ่อนไหว” ต้องถูกติ๊ก",
                         "ยินยอมข้อมูลอ่อนไหว must be ticked")),
                ],
                note=(
                    "เมื่อครบทุกข้อ ปุ่ม “ยืนยัน” ด้านล่างจะเปลี่ยนเป็นสีส้มเข้มและกดได้ "
                    "ภาพนี้บันทึกจากบิลด์รุ่นก่อน จึงมีปุ่ม “ดาวน์โหลดเอกสาร” ใต้ช่อง NDID "
                    "ปัจจุบันไม่มีปุ่มนั้นแล้ว — เอกสารอ่านได้ในแอปเท่านั้น",
                    "Once everything is done the ยืนยัน button turns solid orange and becomes "
                    "tappable. This image is from an earlier build, so it still shows a "
                    "ดาวน์โหลดเอกสาร button under the NDID row; the current app does not have "
                    "it — the documents are read in the app only.",
                ),
            ),
            dict(
                num="2.16", slug="declaration", img="45-declaration.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("คำรับรองของผู้กู้",
                     "ข้อความคงที่ในหน้าจอ",
                     "ไม่มี API"),
                    ("ปุ่ม ยืนยัน",
                     "PLoanContractApi submit",
                     "POST /ploan (bearer auth, multipart/form-data)"),
                ]),
                title=("คำรับรองของผู้กู้", "The borrower's declaration"),
                items=[
                    (1, None,
                        ("ข้อความรับรองว่าข้อมูลที่ให้ไว้ถูกต้องและตรงตามความเป็นจริง "
                         "และผู้กู้มีอำนาจทำสัญญานี้",
                         "you declare that the information given is true and correct, and "
                         "that you have the authority to enter this contract")),
                    (2, "ยืนยัน",
                        ("กดเพื่อส่งคำขอ หลังจากนี้แก้ไขข้อมูลไม่ได้",
                         "submits the request; nothing can be changed afterwards")),
                ],
            ),
            dict(
                num="2.17", slug="submitted", img="50-submitted.png",
                defs=("การเชื่อมโยงข้อมูล (model / API)", "Data mapping (model / API)", [
                    ("ยอดเงินที่จะได้รับ",
                     "PLoanFlow.payoutAmount",
                     "ตรงกับ payload transfer_amount ที่ส่งไป"),
                    ("เลขที่รายการ",
                     "PLoanSuccessPage.transNo",
                     "POST /ploan response body.trans_no"),
                    ("ปุ่ม กลับสู่หน้าแรก",
                     "กลับไปที่ native host app",
                     "ไม่มี API"),
                    ("หน้าจอ / Screen",
                     "lib/p_loan/application/",
                     "p_loan_success_page.dart"),
                ]),
                title=("ส่งคำขอเรียบร้อย", "Request submitted"),
                items=[
                    (1, "ยอดเงินที่จะได้รับ",
                        ("ยอดสุทธิที่จะโอนเข้าบัญชีของท่าน",
                         "the net amount that will be paid into your account")),
                    (2, "เลขที่รายการ",
                        ("เลขอ้างอิงของคำขอ ใช้เมื่อต้องติดต่อสอบถามสถานะ แนะนำให้บันทึกไว้",
                         "the request's reference number — keep it for any follow-up")),
                    (3, "กลับสู่หน้าแรก",
                        ("กดเพื่อกลับไปยังแอปศรีสวัสดิ์",
                         "returns you to the ศรีสวัสดิ์ app")),
                ],
                note=(
                    "หลังส่งคำขอ สัญญานั้นจะขอสินเชื่อเพิ่มซ้ำอีกไม่ได้จนกว่าคำขอนี้จะเสร็จสิ้น "
                    "ติดตามสถานะได้จากเมนู “ติดตามสถานะ” ในหน้าแรกของแอป",
                    "After submitting, that contract cannot raise another request until this "
                    "one is finished. Track it from ติดตามสถานะ on the app's home screen.",
                ),
            ),
        ],
    ),
]

# -------------------------------------------------------------------- issues
ISSUES = [
    ("A1",
     ("ภาพหน้าจอบันทึกจากเครื่องจริงบนระบบ UAT", "Screenshots come from a real device on UAT"),
     ("ภาพส่วนใหญ่ในคู่มือนี้บันทึกเมื่อ 4 สิงหาคม 2569 จากโทรศัพท์จริง "
      "เดินตามเส้นทางจริง คือ แอปศรีสวัสดิ์ → หน้าเติมวงเงิน → วงเงินอเนกประสงค์ (เส้นทางในขณะนั้น) "
      "บนบิลด์เว็บรุ่น 61 และ 62 ของระบบทดสอบ UAT "
      "ตัวเลขที่เห็นจึงเป็นของคำขอจริงหนึ่งรายการ (จัดวงเงิน 2,000 บาท 24 งวด) "
      "เป็นเพียงตัวอย่าง ไม่ใช่เงื่อนไขที่เสนอให้ท่าน",
      "Most images here were captured on 4 August 2026 from a real phone, walking the "
      "real path of the time — ศรีสวัสดิ์ app → top-up screen → วงเงินอเนกประสงค์ — on UAT web builds "
      "61 and 62. The figures are therefore one real request (฿2,000 over 24 months). "
      "They are an example, not an offer."),
     None),
    ("A2",
     ("การปิดบังข้อมูลส่วนบุคคล", "What is masked, and why"),
     ("เพราะภาพมาจากบัญชีจริงบนระบบทดสอบ ทุกอย่างที่ระบุตัวบุคคลจึงถูกพิกเซลปิด คือ "
      "ชื่อ-สกุล เลขบัตรประชาชน เลขที่บัญชีธนาคาร เลขที่สัญญา เลขทะเบียนรถ เบอร์โทรศัพท์ "
      "และที่อยู่ทั้งสี่รายการ หัวข้อและโครงหน้าจอยังเห็นครบ "
      "ตัวเลขยอดเงินในบทที่ 2 ไม่ได้ปิด เพราะเป็นสิ่งที่คู่มืออธิบาย และไม่ระบุตัวผู้ใดเมื่อไม่มีชื่อกำกับ "
      "ส่วนภาพ 1.1 ปิดตัวเลขด้วย เพราะแสดงฐานะสินเชื่อเดิมของลูกค้ารายนั้น "
      "หากต้องการฉบับที่ไม่ปิดบังเพื่อใช้ภายใน สร้างใหม่ได้จากไฟล์ต้นฉบับใน docs/raw/",
      "Because the captures come from a real account on the test system, everything that "
      "identifies a person is pixelated: name, national ID, bank account number, contract "
      "number, plate, phone number and all four addresses. Labels and layout are untouched. "
      "Money figures in chapter 2 are left readable — they are what the manual explains, and "
      "they identify nobody once the name and contract are gone. Image 1.1 does have "
      "its figures masked, because they show that customer's existing credit position. An "
      "unmasked rebuild for internal use is possible from the originals in docs/raw/."),
     None),
    ("A3",
     ("ห้าภาพยังเป็นบิลด์รุ่นก่อน", "Five images are still from the earlier build"),
     ("ภาพ 2.1, 2.7, 2.15, 2.16 และ 2.17 ยังเป็นภาพชุดเดิม ที่บันทึกจากเบราว์เซอร์ "
      "บนข้อมูลจำลอง (สัญญา MOCK-M-6701001 ยอด 35,000 บาท) ตัวเลขจึงไม่ตรงกับภาพอื่น "
      "และมีสองจุดที่ต่างจากแอปปัจจุบัน คือ ภาพ 2.1 พาดหัวยอดเงินว่า “ยอดจัดสินเชื่อใหม่” "
      "ซึ่งตอนนี้เขียนว่า “ยอดจัดวงเงินอเนกประสงค์” และภาพ 2.15 ยังมีปุ่ม “ดาวน์โหลดเอกสาร” "
      "ซึ่งถูกถอดออกไปแล้ว ทั้งสองจุดมีหมายเหตุกำกับไว้ที่ภาพนั้นด้วย "
      "ลำดับขั้นตอนและปุ่มอื่นๆ ตรงกับของจริงทั้งหมด",
      "Images 2.1, 2.7, 2.15, 2.16 and 2.17 are still the first edition's browser "
      "captures on fixture data (contract MOCK-M-6701001, ฿35,000), so their figures do not "
      "match the others. Two of them also differ from the current app: 2.1 heads the amount "
      "ยอดจัดสินเชื่อใหม่ where it now reads ยอดจัดวงเงินอเนกประสงค์, and 2.15 still shows a "
      "ดาวน์โหลดเอกสาร button that has since been removed. Both are flagged on the image "
      "itself. Everything else — the order, the other buttons — matches the live app."),
     None),
    ("A4",
     ("รายชื่อผู้ให้บริการ NDID ดึงมาสดจากระบบ", "The NDID provider list is live"),
     ("ในแอปจริง ตารางผู้ให้บริการในหน้า 2.11 ดึงมาจากระบบ NDID ทุกครั้ง "
      "รายชื่อและโลโก้ที่ท่านเห็นจึงอาจต่างจากภาพ และกลุ่มบน “ผู้ให้บริการที่เคยลงทะเบียน NDID” "
      "จะแสดงเฉพาะที่ตรงกับเลขบัตรประชาชนของท่านเท่านั้น จึงว่างเปล่าได้ถ้าท่านยังไม่เคยลงทะเบียน "
      "โลโก้แสดงได้สูงสุด 4 ช่องในกลุ่มบน ช่องอื่นแสดงเป็นอักษรย่อ",
      "In the app, the provider grid on 2.11 is fetched from NDID every time, so the names "
      "and logos you see may differ from the image. The top group shows only providers "
      "matched to your own national ID, so it is legitimately empty if you have never "
      "registered. At most 4 tiles in the top group show a logo; the rest show initials."),
     None),
    ("A5",
     ("เวลาให้บริการ 07:00–20:30", "Service hours are 07:00–20:30"),
     ("ระบบเปิดให้ขอสินเชื่อเพิ่มเวลา 07:00 ถึง 20:30 เท่านั้น "
      "นอกเวลานี้จะขึ้นข้อความ “ท่านสามารถขอสินเชื่อได้ในเวลา 07:00 ถึง 20:30 เท่านั้น” "
      "เป็นเงื่อนไขของระบบหลังบ้าน ไม่ใช่ข้อผิดพลาดของแอป",
      "Top-up requests are only accepted between 07:00 and 20:30; outside that window the "
      "app shows the server's own message. This is a backend rule, not an app fault."),
     None),
    ("A6",
     ("บางสัญญายังขอสินเชื่อเพิ่มไม่ได้", "Some contracts are not eligible yet"),
     ("หากสัญญายังไม่เข้าเงื่อนไข ระบบจะแจ้งว่า “ขออภัย รายการนี้ยังไม่สามารถทำผ่านแอปได้ "
      "กรุณาติดต่อสาขาเจ้าของบัญชี หรือโทร 1652” "
      "กรณีนี้ให้ติดต่อสาขาตามข้อความ ไม่ใช่ข้อผิดพลาดของแอป",
      "A contract that does not qualify returns the server's message telling the customer to "
      "contact the branch that owns the account, or call 1652. Follow the message — it is "
      "not an app fault."),
     None),
    ("A7",
     ("ยอดเงินหลายตัวยังเป็น int", "Several money values are still int"),
     ("ระหว่างทำตารางการเชื่อมโยงข้อมูล พบว่า LoanAmountDetail ประกาศ defaultTopupAmount, "
      "installmentAmount, minAmountWithRate, maxTopupAmount, transferAmount และ osBalance "
      "เป็น int และ PLoanFlow.requestedAmount กับ payoutAmount ก็เป็น int ด้วย "
      "ขณะที่ /topup/detail ส่งค่าทศนิยม (สตางค์) มา ค่าที่แสดงและค่าที่ส่งไปใน loan_amount "
      "กับ transfer_amount จึงถูกตัดเศษ เป็นข้อสังเกตจากโค้ด ไม่ได้ทดสอบซ้ำในแอป "
      "repo LandAndHouseWeb แก้เป็น double แล้ว และ topup_data.dart ของแอปมือถือเป็น double อยู่แล้ว",
      "While building the mapping tables I noticed LoanAmountDetail declares "
      "defaultTopupAmount, installmentAmount, minAmountWithRate, maxTopupAmount, "
      "transferAmount and osBalance as int, and PLoanFlow.requestedAmount / payoutAmount "
      "are int too — while /topup/detail returns decimals (satang). Displayed values and "
      "the loan_amount / transfer_amount actually submitted are therefore truncated. "
      "A code observation, not a re-test in the app. LandAndHouseWeb has already moved "
      "these to double, and the mobile app's topup_data.dart is double already."),
     None),
    ("A8",
     ("ภาพขั้นตอน NDID บันทึกจากเบราว์เซอร์", "The NDID images come from a browser"),
     ("ภาพ 2.10–2.13 บันทึกเมื่อ 27 ตุลาคม 2569 จากบิลด์เว็บรุ่น 223 ของระบบ UAT "
      "โดยเปิดในเบราว์เซอร์ ไม่ใช่ในแอป จึงไม่มีข้อมูลส่วนบุคคล แต่มีสามจุดที่ต่างจากที่ลูกค้าเห็นในแอป คือ "
      "หน้า 2.11 แสดงรายชื่อธนาคารตัวอย่างแทนรายชื่อจริงจาก NDID "
      "หน้า 2.12 มีปุ่ม “จำลองยืนยันตัวตนสำเร็จ” ซึ่งในแอปคือปุ่ม “ตรวจสอบสถานะ” "
      "และ Transaction Ref แสดง 000000001 แทนเลขจริงจากระบบ "
      "ขั้นตอนนี้เปลี่ยนจากฉบับก่อนสามเรื่อง คือ มีหน้าข้อตกลง NDID (2.10) ก่อนเลือกผู้ให้บริการ "
      "เลือกผู้ให้บริการที่ยังไม่ลงทะเบียนได้แล้ว และข้อความผิดพลาดใช้ข้อความมาตรฐานของ NDID "
      "ส่วนหน้าเติมวงเงินของ LandAndHouseWeb (ข้อ 1.2 ในฉบับก่อน) ถูกนำออก "
      "เพราะตั้งแต่ 14 ตุลาคม 2569 ปุ่ม “เติมวงเงิน” เปิดบริการเติมวงเงินของแอปนี้ ซึ่งไม่มีทางไปยังวงเงินอเนกประสงค์",
      "Images 2.10–2.13 were captured on 27 October 2026 from UAT web build 223, opened in "
      "a browser rather than in the app. They carry no personal data, but three things "
      "differ from what a customer sees: 2.11 shows sample banks instead of NDID's live "
      "list, 2.12 has a จำลองยืนยันตัวตนสำเร็จ button where the app has ตรวจสอบสถานะ, and "
      "its Transaction Ref reads 000000001 instead of a real one. This step changed in "
      "three ways since the last edition: an NDID agreement screen (2.10) now comes before "
      "the provider list, unregistered providers can be picked, and failures use NDID's "
      "standard messages. The LandAndHouseWeb top-up card (1.2 in the last edition) was "
      "removed: since 14 October 2026 the เติมวงเงิน button opens this app's own top-up "
      "service, which has no way into วงเงินอเนกประสงค์."),
     None),
]
