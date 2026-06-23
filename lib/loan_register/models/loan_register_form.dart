import '../../models/customer_detail.dart';

/// In-memory holder for the loan-register (สมัครสินเชื่อ) wizard.
///
/// UI-only build: this carries the values shown across the step pages and is
/// passed page → page. It is seeded with the mock data from the design so the
/// screens render exactly like slide 7. No persistence / backend wiring here.
class LoanRegisterForm {
  // ── Step 1: ข้อมูลลูกค้า ─────────────────────────────────────────────
  String firstName;
  String lastName;
  String phone;
  String birthDate; // Buddhist era dd/MM/yyyy
  String thaiId;
  String gender;
  String nationality;
  String cardIssueDate;
  String cardExpiryDate;

  // ข้อมูลที่อยู่
  String idCardAddress;
  String workAddress;
  String currentAddress;
  AddressChoice addressChoice;

  // ข้อมูลอาชีพ
  String occupationGroup;
  String monthlyIncome;
  String workTenure;

  // ── Step 2: ข้อมูลหลักประกัน ─────────────────────────────────────────
  /// Base64 of the captured collateral document, returned by the native host's
  /// camera (for the future OCR API call). Empty when nothing captured yet.
  /// May be raw base64 or a `data:image/...;base64,` URL.
  String documentImageBase64;
  String productGroup;
  String brand;
  String model;
  String color;
  String productDetail;
  String chassisNumber;
  String engineNumber;
  String manufactureYear;
  String registrationNumber;
  String registrationProvince;
  String registrationExpiry;

  // ── Step 3: ข้อมูลสินเชื่อ ───────────────────────────────────────────
  String maxAmount; // วงเงินที่ได้รับ
  String requestedAmount; // วงเงินที่ต้องการ
  int installments; // จำนวนงวด
  String installmentAmount; // ค่างวดแต่ละงวด
  String lastInstallmentAmount; // ค่างวดงวดสุดท้าย
  String contractDate; // วันที่ทำสัญญา
  String firstPaymentDate; // ชำระงวดแรก
  String amountReceived; // จำนวนเงินที่ได้รับ

  // ข้อมูลการโอนเงิน
  String transferType; // ประเภทการโอนเงิน
  String bankAccount; // บัญชีธนาคารลูกค้า
  String accountName; // ชื่อบัญชี
  String accountType; // ประเภทบัญชี
  String accountNumber; // เลขบัญชี

  // ── Step 4: เอกสารแนบ / ลงนาม + ยืนยันตัวตน NDID ─────────────────────
  /// Whether the contract documents (เอกสารประกอบสัญญา) have been reviewed,
  /// signed and the customer's identity verified through NDID. Gates the
  /// step-4 "ถัดไป" and flips the contract-docs card to its verified state.
  bool ndidVerified;

  // ── Step 5: นัดหมายส่งเอกสาร ──────────────────────────────────────────
  String appointmentBranch; // สาขานัดหมาย
  String appointmentDateTime; // วันที่-เวลานัดหมาย (Buddhist dd/MM/yyyy HH:mm)

  LoanRegisterForm({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.birthDate = '',
    this.thaiId = '',
    this.gender = '',
    this.nationality = '',
    this.cardIssueDate = '',
    this.cardExpiryDate = '',
    this.idCardAddress = '',
    this.workAddress = '',
    this.currentAddress = '',
    this.addressChoice = AddressChoice.idCard,
    this.occupationGroup = '',
    this.monthlyIncome = '',
    this.workTenure = '',
    this.documentImageBase64 = '',
    this.productGroup = '',
    this.brand = '',
    this.model = '',
    this.color = '',
    this.productDetail = '',
    this.chassisNumber = '',
    this.engineNumber = '',
    this.manufactureYear = '',
    this.registrationNumber = '',
    this.registrationProvince = '',
    this.registrationExpiry = '',
    this.maxAmount = '',
    this.requestedAmount = '',
    this.installments = 12,
    this.installmentAmount = '',
    this.lastInstallmentAmount = '',
    this.contractDate = '',
    this.firstPaymentDate = '',
    this.amountReceived = '',
    this.transferType = '',
    this.bankAccount = '',
    this.accountName = '',
    this.accountType = '',
    this.accountNumber = '',
    this.ndidVerified = false,
    this.appointmentBranch = '',
    this.appointmentDateTime = '',
  });

  /// Mock data matching slide 7 so the flow renders fully populated.
  factory LoanRegisterForm.mock() => LoanRegisterForm(
        firstName: 'เบนรา',
        lastName: 'ยอดเสฉ',
        phone: '090-333-4571',
        birthDate: '01/09/2533',
        thaiId: '1-3345-00760-99-9',
        gender: 'หญิง',
        nationality: 'ไทย',
        cardIssueDate: '01/09/2566',
        cardExpiryDate: '31/08/2576',
        idCardAddress: '62/122 ม.4 ต.บางพลับ อ.ปากเกร็ด นนทบุรี 11120',
        workAddress: '62/122 ม.4 ต.บางพลับ อ.ปากเกร็ด นนทบุรี 11120',
        currentAddress: '62/122 ม.4 ต.บางพลับ อ.ปากเกร็ด นนทบุรี 11120',
        occupationGroup: '',
        monthlyIncome: '',
        workTenure: '',
        productGroup: '[MC] - รถมอเตอร์ไซค์',
        brand: 'YAMAHA',
        model: 'FINN-YAMAHA-MC',
        color: 'ฟ้า',
        productDetail: 'FINN-YAMAHA-MC 115cc',
        chassisNumber: '',
        engineNumber: 'E3W5E-507835',
        manufactureYear: '2019',
        registrationNumber: '1กฬ2494',
        registrationProvince: 'อุบลราชธานี',
        registrationExpiry: '16/12/2572',
        maxAmount: '15,000.00',
        requestedAmount: '15,000.00',
        installments: 12,
        installmentAmount: '1,491.00',
        lastInstallmentAmount: '1,494.34',
        contractDate: '17/02/2569',
        firstPaymentDate: '17/02/2569',
        amountReceived: '15,000.00',
        transferType: 'บัญชีลูกค้า',
        bankAccount: 'ธนาคาร เพื่อการเกษตรและสหกรณ์การเกษตร',
        accountName: 'นางสาวมนทิรา ยอดเสฉ',
        accountType: 'บัญชีออมทรัพย์',
        accountNumber: '016502637997',
      );

  /// Seeds step 1 (ข้อมูลลูกค้า) from the parsed [CustomerDetail], keeping the
  /// mock collateral/loan data (steps 2–3) so the rest of the flow still
  /// renders. Fields the customer record doesn't provide (gender's exact value,
  /// ID-card issue/expiry dates, occupation) are left blank for the user to
  /// fill.
  factory LoanRegisterForm.fromCustomerDetail(CustomerDetail c) {
    final address = _composeAddress(c);
    return LoanRegisterForm.mock()
      ..firstName = c.firstName.trim()
      ..lastName = c.lastName.trim()
      ..phone = _formatPhone(c.phoneNumber)
      ..birthDate = _formatBuddhistDate(c.dob)
      ..thaiId = _formatThaiId(c.thaiId)
      ..gender = _genderFromTitle(c.title)
      ..nationality = 'ไทย'
      ..cardIssueDate = ''
      ..cardExpiryDate = ''
      ..idCardAddress = address
      ..workAddress = address
      ..currentAddress = address
      ..occupationGroup = ''
      ..monthlyIncome = ''
      ..workTenure = ''
      // Step 2 (ข้อมูลหลักประกัน) starts empty — filled by OCR / by hand.
      ..documentImageBase64 = ''
      ..productGroup = ''
      ..brand = ''
      ..model = ''
      ..color = ''
      ..productDetail = ''
      ..chassisNumber = ''
      ..engineNumber = ''
      ..manufactureYear = ''
      ..registrationNumber = ''
      ..registrationProvince = ''
      ..registrationExpiry = '';
  }

  static String _formatPhone(String raw) {
    if (raw.isEmpty) return '';
    return raw.replaceAllMapped(
      RegExp(r'^(\d{3})(\d{3})(\d+)$'),
      (m) => '${m[1]}-${m[2]}-${m[3]}',
    );
  }

  static String _formatThaiId(String raw) {
    if (raw.isEmpty) return '';
    return raw.replaceAllMapped(
      RegExp(r'^(\d{1})(\d{4})(\d{5})(\d{2})(\d+)$'),
      (m) => '${m[1]}-${m[2]}-${m[3]}-${m[4]}-${m[5]}',
    );
  }

  static String _genderFromTitle(String? title) {
    final t = title ?? '';
    if (t.contains('นาย')) return 'ชาย';
    if (t.contains('นาง') || t.contains('น.ส')) return 'หญิง';
    return '';
  }

  /// Formats a [DateTime] as Buddhist-era `dd/MM/yyyy`.
  ///
  /// The API may send the year already in Buddhist era (e.g. `2514-02-13`) or
  /// in Gregorian (`1971-02-13`); years past ~2200 are assumed to already be
  /// Buddhist, otherwise 543 is added.
  static String _formatBuddhistDate(DateTime? date) {
    if (date == null) return '';
    final buddhistYear = date.year > 2200 ? date.year : date.year + 543;
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/$buddhistYear';
  }

  static String _composeAddress(CustomerDetail c) {
    final parts = [
      c.addressDetails,
      c.addressSubDistrict,
      c.addressDistinct,
      c.addressProvince,
      c.addressPostalCode,
    ].where((e) => e.trim().isNotEmpty);
    return parts.join(' ');
  }
}

/// Which address the customer chose to use as the contact/current address.
enum AddressChoice { idCard, work, custom }
