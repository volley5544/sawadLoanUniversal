#!/usr/bin/env python3
"""Content source for the วงเงินอเนกประสงค์ (P-Loan Extra) user manual.

    python3 scripts/build_docs.py docs/content.py
    bash    scripts/build_pdf.sh  docs/user-manual.html

Scope: the customer-facing path only — the two entry points inside the
ศรีสวัสดิ์ app, then the three steps this build actually shows when it is
opened from the top-up card (จำนวนงวด → ข้อมูลส่วนตัว → สรุป/ยืนยัน).
Steps 1, 2 and 4 of the six-step wizard are skipped on that path by design:
the top-up card already showed the amount, and an existing contract's
collateral is already on file.

Re-shot 2026-08-04 on a real device against live UAT (web build 61/62). That
replaced the browser-on-fixtures captures the first edition used, and it moved
three screens that had only been described in prose — the four addresses, the
documents + NDID block, and the two consents — into images of their own.
Six screens (2.1, 2.7, 2.12, 2.14, 2.15, 2.16) are still the older captures;
appendix A3 says exactly what differs on them.
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
    version="UAT · สินเชื่อเพิ่มจากสัญญาเดิม (P-Loan Extra) · web 61–62",
    url="sawad-loan-universal-uat.web.app",
    date="2026-08-04",
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
            "วงเงินอเนกประสงค์เริ่มต้นในแอปศรีสวัสดิ์ มีสองทางเข้า ทั้งสองทางไปยังหน้าจอเดียวกัน",
            "วงเงินอเนกประสงค์ starts inside the ศรีสวัสดิ์ app. There are two ways in, "
            "and both reach the same screens.",
        ),
        screens=[
            dict(
                num="1.1", slug="home", img="01-home.png",
                title=("หน้าแรกของแอปศรีสวัสดิ์", "The ศรีสวัสดิ์ home screen"),
                items=[
                    (1, "เติมวงเงิน",
                        ("กดเพื่อเปิดหน้าเติมวงเงิน แล้วเลือกวงเงินอเนกประสงค์ที่หน้านั้น",
                         "opens the top-up screen, where you then pick วงเงินอเนกประสงค์")),
                    (2, "วงเงินอเนกประสงค์",
                        ("ปุ่มในกล่อง “สิทธิพิเศษเฉพาะคุณ” บนบัตรสัญญา กดเพื่อเข้าสู่ขั้นตอนการสมัครทันที",
                         "in the สิทธิพิเศษเฉพาะคุณ box on the contract card — goes straight "
                         "into the application")),
                ],
                note=(
                    "ปุ่มนี้จะปรากฏบนบัตรของสัญญาที่เข้าเงื่อนไขเท่านั้น "
                    "หากสัญญายังไม่เข้าเงื่อนไข หรือมีคำขออยู่แล้ว ระบบจะแจ้งเหตุผลเมื่อกดเข้าไป",
                    "The button appears only on a contract that qualifies. If the contract "
                    "is not yet eligible, or already has a request open, the reason is shown "
                    "when you continue.",
                ),
            ),
            dict(
                num="1.2", slug="topup-card", img="02-topup-card.png",
                title=("หน้าเติมวงเงิน", "The top-up screen"),
                items=[
                    (1, "วงเงินอเนกประสงค์",
                        ("กดปุ่มในกล่อง “สิทธิพิเศษเฉพาะคุณ” เพื่อเริ่มขอสินเชื่อเพิ่ม",
                         "tap it in the สิทธิพิเศษเฉพาะคุณ box to start the application")),
                ],
                note=(
                    "หน้านี้คือขั้นที่ 1 ของ 4 ขั้น เพราะเป็นหน้าที่แสดงวงเงินที่อนุมัติให้ท่านแล้ว "
                    "เมื่อเข้าสู่ขั้นตอนถัดไป แถบขั้นตอนจะเริ่มนับจาก 2 "
                    "ปุ่มย้อนกลับในหน้าจอถัดไปจะพาท่านกลับมาที่หน้านี้",
                    "This screen is step 1 of 4: it is where the approved amount is shown to "
                    "you. The step bar on the following screens therefore starts at 2, and "
                    "Back on the first of them returns you here.",
                ),
                defs=("คำที่พบบนหน้านี้", "Terms on this screen", [
                    ("วงเงินสินเชื่อเดิม",
                     "วงเงินของสัญญาที่ท่านถืออยู่",
                     "the limit on the contract you already hold"),
                    ("วงเงินอนุมัติใหม่",
                     "วงเงินรวมที่อนุมัติให้สำหรับสัญญาใหม่",
                     "the total limit approved for the new contract"),
                    ("วงเงินเพิ่มพิเศษ",
                     "วงเงินส่วนเพิ่มที่ได้รับเป็นสิทธิพิเศษ นี่คือยอดที่วงเงินอเนกประสงค์จะจัดให้",
                     "extra headroom granted as a special offer — this is the amount "
                     "วงเงินอเนกประสงค์ finances"),
                    ("เงินคงเหลือโอนเข้าบัญชี",
                     "จำนวนเงินที่จะโอนเข้าบัญชีจริง หากท่านเลือกเติมวงเงินแบบรับเงินสด",
                     "what reaches your bank account if you take the cash top-up instead"),
                ]),
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
                defs=("รายการยอดเงินบนหน้าสรุป", "The figures on the summary", [
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
                ]),
            ),
            dict(
                num="2.6", slug="identity-empty", img="31-identity-empty.png",
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
                title=("เอกสารประกอบสัญญาและการลงนาม", "The documents, and signing them"),
                items=[
                    (1, "เอกสารประกอบสัญญา",
                        ("สามฉบับ คือ ใบคำขอสินเชื่อใหม่ ใบรับเงิน และเอกสารสัญญา "
                         "กดทีละฉบับเพื่อเปิดอ่านและกดยอมรับ",
                         "three of them — the loan request form, the receipt and the "
                         "contract. Tap each one to read it and accept it")),
                    (2, "ลงนามเอกสารและยืนยันตัวตน NDID",
                        ("กดเพื่อเริ่มลงนามด้วย NDID แทนการเซ็นชื่อ",
                         "starts NDID signing, which replaces a written signature")),
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
                num="2.10", slug="ndid-banks", img="40-ndid-banks.png",
                title=("เลือกผู้ให้บริการยืนยันตัวตน NDID", "Choose your NDID provider"),
                items=[
                    (1, "ผู้ให้บริการที่เคยลงทะเบียน NDID",
                        ("เลือกธนาคารหรือผู้ให้บริการที่ท่านลงทะเบียน NDID ไว้แล้ว "
                         "กดได้เฉพาะรายชื่อในกลุ่มนี้",
                         "pick a bank or provider you have already registered with for NDID; "
                         "only this group is tappable")),
                    (2, "ผู้ให้บริการที่ยังไม่ลงทะเบียน NDID",
                        ("รายชื่อนี้เป็นสีจาง กดไม่ได้ ต้องไปลงทะเบียน NDID กับที่นั่นก่อน",
                         "these are greyed out and cannot be selected; register for NDID with "
                         "them first")),
                    (3, "ถัดไป",
                        ("กดเมื่อเลือกแล้ว เพื่อส่งคำขอยืนยันตัวตน",
                         "sends the verification request once one is selected")),
                ],
                note=(
                    "หากกลุ่มบนว่างเปล่า แปลว่าท่านยังไม่ได้ลงทะเบียน NDID กับที่ใดเลย "
                    "ต้องไปลงทะเบียนกับธนาคารที่ท่านเป็นลูกค้าก่อน จึงจะทำขั้นตอนนี้ต่อได้ "
                    "รายชื่อทั้งหมดดึงมาจากระบบ NDID จึงอาจต่างจากภาพนี้",
                    "An empty top group means you have not registered for NDID anywhere yet; "
                    "register with a bank you hold an account at before continuing. The whole "
                    "list comes live from NDID, so it may differ from this image.",
                ),
                defs=("NDID", "NDID", [
                    ("NDID",
                     "บริการยืนยันตัวตนดิจิทัลผ่านธนาคารที่ท่านเป็นลูกค้า "
                     "ใช้ลงนามเอกสารสัญญาแทนการเซ็นชื่อ",
                     "digital identity verification through a bank you already bank with, "
                     "used here to sign the contract instead of a written signature"),
                ]),
            ),
            dict(
                num="2.11", slug="ndid-waiting", img="42-ndid-waiting.png",
                title=("รอยืนยันตัวตนในแอปธนาคาร", "Waiting for the bank app"),
                items=[
                    (1, None,
                        ("เวลาที่เหลือสำหรับทำรายการ ต้องยืนยันในแอปธนาคารภายในเวลานี้ "
                         "ทำได้ครั้งเดียวต่อหนึ่งรายการ",
                         "the time left to finish; verify in the bank's app before it runs "
                         "out — one attempt per request")),
                    (2, "ตรวจสอบสถานะ",
                        ("กดเพื่อถามผลจากระบบทันที ใช้เมื่อยืนยันในแอปธนาคารเสร็จแล้ว "
                         "แต่หน้านี้ยังนับถอยหลังอยู่",
                         "asks for the result right away — use it if you finished in the bank "
                         "app but this screen is still counting down")),
                    (3, "ยกเลิก",
                        ("กดเพื่อยกเลิกคำขอยืนยันตัวตนนี้",
                         "cancels this verification request")),
                ],
                note=(
                    "ขั้นตอนนี้ทำในแอปของธนาคารที่ท่านเลือก ไม่ใช่ในหน้าจอนี้ "
                    "เปิดแอปธนาคาร ทำตามขั้นตอนของธนาคาร แล้วกลับมายังหน้านี้ "
                    "หน้าจอจะตรวจผลให้ทันทีที่กลับมา หรือกด “ตรวจสอบสถานะ” ก็ได้ "
                    "บรรทัด Transaction Ref คือเลขอ้างอิงของรายการยืนยันตัวตนครั้งนี้",
                    "This step happens in your bank's own app, not on this screen. Open the "
                    "bank app, follow its steps, then come back — the screen checks as soon "
                    "as you return, and ตรวจสอบสถานะ checks on demand. The Transaction Ref "
                    "line is this verification request's own reference.",
                ),
            ),
            dict(
                num="2.12", slug="ndid-done", img="43-ndid-done.png",
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
                    "หากธนาคารปฏิเสธ หมดเวลา หรือท่านยกเลิก หน้านี้จะแจ้งข้อผิดพลาด "
                    "และมีปุ่มให้ลองใหม่",
                    "If the bank rejects it, the request times out, or you cancel, this "
                    "screen reports the error and offers a retry.",
                ),
            ),
            dict(
                num="2.13", slug="consents", img="36-consents.png",
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
                num="2.14", slug="ready", img="34-ready-to-submit.png",
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
                num="2.15", slug="declaration", img="45-declaration.png",
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
                num="2.16", slug="submitted", img="50-submitted.png",
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
      "เดินตามเส้นทางจริง คือ แอปศรีสวัสดิ์ → หน้าเติมวงเงิน → วงเงินอเนกประสงค์ "
      "บนบิลด์เว็บรุ่น 61 และ 62 ของระบบทดสอบ UAT "
      "ตัวเลขที่เห็นจึงเป็นของคำขอจริงหนึ่งรายการ (จัดวงเงิน 2,000 บาท 24 งวด) "
      "เป็นเพียงตัวอย่าง ไม่ใช่เงื่อนไขที่เสนอให้ท่าน",
      "Most images here were captured on 4 August 2026 from a real phone, walking the "
      "real path — ศรีสวัสดิ์ app → top-up screen → วงเงินอเนกประสงค์ — on UAT web builds "
      "61 and 62. The figures are therefore one real request (฿2,000 over 24 months). "
      "They are an example, not an offer."),
     None),
    ("A2",
     ("การปิดบังข้อมูลส่วนบุคคล", "What is masked, and why"),
     ("เพราะภาพมาจากบัญชีจริงบนระบบทดสอบ ทุกอย่างที่ระบุตัวบุคคลจึงถูกพิกเซลปิด คือ "
      "ชื่อ-สกุล เลขบัตรประชาชน เลขที่บัญชีธนาคาร เลขที่สัญญา เลขทะเบียนรถ เบอร์โทรศัพท์ "
      "และที่อยู่ทั้งสี่รายการ หัวข้อและโครงหน้าจอยังเห็นครบ "
      "ตัวเลขยอดเงินในบทที่ 2 ไม่ได้ปิด เพราะเป็นสิ่งที่คู่มืออธิบาย และไม่ระบุตัวผู้ใดเมื่อไม่มีชื่อกำกับ "
      "ส่วนภาพ 1.1 และ 1.2 ปิดตัวเลขด้วย เพราะแสดงฐานะสินเชื่อเดิมของลูกค้ารายนั้น "
      "หากต้องการฉบับที่ไม่ปิดบังเพื่อใช้ภายใน สร้างใหม่ได้จากไฟล์ต้นฉบับใน docs/raw/",
      "Because the captures come from a real account on the test system, everything that "
      "identifies a person is pixelated: name, national ID, bank account number, contract "
      "number, plate, phone number and all four addresses. Labels and layout are untouched. "
      "Money figures in chapter 2 are left readable — they are what the manual explains, and "
      "they identify nobody once the name and contract are gone. Images 1.1 and 1.2 do have "
      "their figures masked, because they show that customer's existing credit position. An "
      "unmasked rebuild for internal use is possible from the originals in docs/raw/."),
     None),
    ("A3",
     ("หกภาพยังเป็นบิลด์รุ่นก่อน", "Six images are still from the earlier build"),
     ("ภาพ 2.1, 2.7, 2.12, 2.14, 2.15 และ 2.16 ยังเป็นภาพชุดเดิม ที่บันทึกจากเบราว์เซอร์ "
      "บนข้อมูลจำลอง (สัญญา MOCK-M-6701001 ยอด 35,000 บาท) ตัวเลขจึงไม่ตรงกับภาพอื่น "
      "และมีสองจุดที่ต่างจากแอปปัจจุบัน คือ ภาพ 2.1 พาดหัวยอดเงินว่า “ยอดจัดสินเชื่อใหม่” "
      "ซึ่งตอนนี้เขียนว่า “ยอดจัดวงเงินอเนกประสงค์” และภาพ 2.14 ยังมีปุ่ม “ดาวน์โหลดเอกสาร” "
      "ซึ่งถูกถอดออกไปแล้ว ทั้งสองจุดมีหมายเหตุกำกับไว้ที่ภาพนั้นด้วย "
      "ลำดับขั้นตอนและปุ่มอื่นๆ ตรงกับของจริงทั้งหมด",
      "Images 2.1, 2.7, 2.12, 2.14, 2.15 and 2.16 are still the first edition's browser "
      "captures on fixture data (contract MOCK-M-6701001, ฿35,000), so their figures do not "
      "match the others. Two of them also differ from the current app: 2.1 heads the amount "
      "ยอดจัดสินเชื่อใหม่ where it now reads ยอดจัดวงเงินอเนกประสงค์, and 2.14 still shows a "
      "ดาวน์โหลดเอกสาร button that has since been removed. Both are flagged on the image "
      "itself. Everything else — the order, the other buttons — matches the live app."),
     None),
    ("A4",
     ("รายชื่อผู้ให้บริการ NDID ดึงมาสดจากระบบ", "The NDID provider list is live"),
     ("ตารางผู้ให้บริการในภาพ 2.10 ดึงมาจากระบบ NDID จริง ณ เวลาที่บันทึกภาพ "
      "รายชื่อและโลโก้ที่ท่านเห็นอาจต่างออกไป และกลุ่มบน “ผู้ให้บริการที่เคยลงทะเบียน NDID” "
      "จะแสดงเฉพาะที่ตรงกับเลขบัตรประชาชนของท่านเท่านั้น จึงว่างเปล่าได้ถ้าท่านยังไม่เคยลงทะเบียน",
      "The provider grid in image 2.10 was fetched live from NDID at capture time; the names "
      "and logos you see may differ. The top group shows only providers matched to your own "
      "national ID, so it is legitimately empty if you have never registered."),
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
]
