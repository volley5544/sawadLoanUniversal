/// **Temporary** fixtures that stand in for the mobile API while the P-Loan
/// endpoints are unavailable. Gated by [kPLoanUseMockData].
///
/// Values are shaped like real responses — same key names, same quirks, same
/// order of magnitude — so the screens exercise the real parsing path and the
/// arithmetic still adds up. They are built by feeding JSON through the real
/// `fromJson` constructors rather than by constructing models directly, so a
/// change to a wire key breaks the mock too instead of letting it drift.
///
/// Delete this file and the `kPLoanUseMockData` guards in
/// `services/p_loan_api.dart` to remove mock mode entirely.
library;

import 'dart:convert';

import '../../../models/customer_address.dart';
import '../../../models/customer_detail.dart';
import 'installment_plan.dart';
import 'loan_amount_detail.dart';
import 'loan_contract.dart';
import 'loan_documents.dart';

/// Latency so loading states are actually visible while demoing.
const Duration kMockLatency = Duration(milliseconds: 350);

/// The customer the mock contracts belong to. The Thai ID here is what
/// [mockThaiIdOnCard] returns, so step 6's identity check passes.
CustomerDetail mockCustomer() => CustomerDetail.fromJson(const {
      'code': '200',
      'thai_id': '1670200003359',
      'title': 'นาย',
      'first_name': 'สมชาย',
      'last_name': 'ใจดี',
      'phone_number': '0863652156',
      'dob': '1990-04-12',
      'email': 'somchai@example.com',
      'hash_thai_id': 'MOCKHASH',
      'is_existing_customer': true,
    });

/// The ID read off the card by the vision endpoint — matches [mockCustomer].
const String mockThaiIdOnCard = '1670200003359';

CustomerAddressBook mockAddressBook() => CustomerAddressBook.fromJson(const {
      'current_address': {
        'address_details': '244/98 หมู่บ้านสุชารี',
        'address_sub_district': 'ทุ่งสองห้อง',
        'address_district': 'หลักสี่',
        'address_province': 'กรุงเทพมหานคร',
        'address_postal_code': '10210',
      },
      'registration_address': {
        'address_details': '99/1 ซอยรามคำแหง 24',
        'address_sub_district': 'หัวหมาก',
        'address_district': 'บางกะปิ',
        'address_province': 'กรุงเทพมหานคร',
        'address_postal_code': '10240',
      },
      'id_card_address': {
        'address_details': '99/1 ซอยรามคำแหง 24',
        'address_sub_district': 'หัวหมาก',
        'address_district': 'บางกะปิ',
        'address_province': 'กรุงเทพมหานคร',
        'address_postal_code': '10240',
      },
      'other_address': {
        'address_details': 'อาคารศรีสวัสดิ์ ชั้น 12',
        'address_sub_district': 'จอมพล',
        'address_district': 'จตุจักร',
        'address_province': 'กรุงเทพมหานคร',
        'address_postal_code': '10900',
      },
      'data_date': '2026-07-27T09:00:00',
    });

/// Two selectable contracts — a motorcycle (2 required photos) and a car
/// (6 required photos) — so both step-4 branches can be demoed.
List<LoanContract> mockContracts() => const [
      _motorcycleContract,
      _carContract,
    ].map(LoanContract.fromJson).toList(growable: false);

const Map<String, dynamic> _motorcycleContract = {
  'contract_name': 'สัญญาเช่าซื้อรถจักรยานยนต์',
  'db_name': 'MOCKDB',
  'contract_no': 'MOCK-M-6701001',
  'branch_code': '1C',
  'branch_name': 'สาขาหลักสี่',
  'contract_bank_type': 'S',
  'contract_bank_account': '1234567890',
  'contract_bank_brandname': 'KBANK',
  'loan_type_code': 'M',
  'loan_type_name': 'สินเชื่อรถจักรยานยนต์',
  'data_date': '2026-07-27T09:00:00',
  'transno': '',
  'request_status': 'ยังไม่ได้ทำรายการเติมเงิน',
  'contract_details': {
    'account_status': 'A',
    'account_type': 'C',
    'can_topup': 'Y',
    'loan_type_code': 'M',
    'loan_type_name': 'สินเชื่อรถจักรยานยนต์',
    'collateral_information': 'ฮอนด้า เวฟ 110i กข 1234',
    'closing_balance': 12000,
    'credit_limit': 35000.0,
    'current_ltv_amount': 42000,
    'comcode': '1C',
    'vehicle_brand': 'HONDA',
    'license_plate_expire_date': '2027-03-31',
  },
  'car_details': {
    'car_registration': 'กข 1234',
    'car_province': 'กรุงเทพมหานคร',
    'car_brand': 'HONDA',
    'car_series': 'Wave 110i',
    'car_chassisNo': 'MOCKCHASSIS001',
    'car_engineNo': 'MOCKENGINE001',
    'car_manufacture_year': '2016',
  },
  'payment_details': {
    'current_date_time': '2026-07-27T09:00:00',
    'installment_amount': 1500,
    'total_installment_number': 24.0,
  },
  'topup_detail': {
    'can_topup': 'Y',
    'default_topup_amount': 35000,
    'fee_amount': 100,
    'balance_receivable': 12500,
    'topup_extra': 0,
    'yield': 250,
    'default_transfer_amount': 22900.0,
  },
};

const Map<String, dynamic> _carContract = {
  'contract_name': 'สัญญาเช่าซื้อรถยนต์',
  'db_name': 'MOCKDB',
  'contract_no': 'MOCK-C-6701002',
  'branch_code': '1C',
  'branch_name': 'สาขาจตุจักร',
  'contract_bank_type': 'S',
  'contract_bank_account': '9876543210',
  'contract_bank_brandname': 'SCB',
  'loan_type_code': 'C',
  'loan_type_name': 'สินเชื่อรถยนต์',
  'data_date': '2026-07-27T09:00:00',
  'transno': '',
  'request_status': 'ยังไม่ได้ทำรายการเติมเงิน',
  'contract_details': {
    'account_status': 'A',
    'account_type': 'C',
    'can_topup': 'Y',
    'loan_type_code': 'C',
    'loan_type_name': 'สินเชื่อรถยนต์',
    'collateral_information': 'โตโยต้า วีออส 1ขค 5678',
    'closing_balance': 180000,
    'credit_limit': 400000.0,
    'current_ltv_amount': 460000,
    'comcode': '1C',
    'vehicle_brand': 'TOYOTA',
    'license_plate_expire_date': '2027-08-15',
  },
  'car_details': {
    'car_registration': '1ขค 5678',
    'car_province': 'กรุงเทพมหานคร',
    'car_brand': 'TOYOTA',
    'car_series': 'Vios 1.5E',
    'car_chassisNo': 'MOCKCHASSIS002',
    'car_engineNo': 'MOCKENGINE002',
    'car_manufacture_year': '2019',
  },
  'payment_details': {
    'current_date_time': '2026-07-27T09:00:00',
    'installment_amount': 8500,
    'total_installment_number': 48.0,
  },
  'topup_detail': {
    'can_topup': 'Y',
    'default_topup_amount': 400000,
    'fee_amount': 500,
    'balance_receivable': 185000,
    'topup_extra': 20000,
    'yield': 1200,
    'default_transfer_amount': 214500.0,
  },
};

/// Limits for the selected contract. Derived from the contract so the numbers
/// on step 2 agree with what step 1 showed.
LoanAmountDetail mockAmountDetail(String contractNo) {
  final isCar = contractNo.contains('-C-');
  final source = isCar ? _carContract : _motorcycleContract;
  final details = source['contract_details'] as Map<String, dynamic>;
  final topup = source['topup_detail'] as Map<String, dynamic>;
  final approved = topup['default_topup_amount'] as int;

  return LoanAmountDetail.fromJson({
    'code': '200',
    'message': '',
    'db_name': source['db_name'],
    'contract_no': source['contract_no'],
    'contract_details': details,
    'car_details': source['car_details'],
    'first_due_date': '2026-08-15',
    'due_day': 15,
    'contract_date': '2024-03-01',
    'default_topup_amount': approved,
    'min_topup_amount': isCar ? 20000 : 5000,
    'max_topup_amount': approved,
    'interest_rate': 1.09,
    'fee_amount': topup['fee_amount'],
    'balance_receivable': topup['balance_receivable'],
    'topup_extra': topup['topup_extra'],
    'interest_paid_flag': 'N',
    'yield': topup['yield'],
    'data_date': '2026-07-27T09:00:00',
    'life_insure_amt': '0',
  });
}

/// Installment options for [loanAmount].
///
/// Interest is computed rather than hardcoded, so changing the amount on
/// step 2 visibly changes the monthly payment — the recalculate-on-change
/// behaviour is the thing worth demoing here.
InstallmentPlan mockInstallmentPlan(int loanAmount) {
  const rate = 1.09; // % per month, matching mockAmountDetail
  List<Map<String, dynamic>> options() => [12, 18, 24, 36].map((tenor) {
        final interest = loanAmount * (rate / 100) * tenor;
        final total = loanAmount + interest;
        final regular = (total / tenor).floor();
        final last = total - (regular * (tenor - 1));
        return <String, dynamic>{
          'tenor': tenor,
          'firstPeriodAmt': regular,
          'regularPeriodAmt': regular,
          'lastPeriodAmt': double.parse(last.toStringAsFixed(2)),
          'totalAmt': double.parse(total.toStringAsFixed(2)),
          'intAmt': double.parse(interest.toStringAsFixed(2)),
          'lastPeriodPromo': 0.0,
          'term': '$tenor',
          'amount': '$loanAmount',
        };
      }).toList();

  return InstallmentPlan.fromJson({
    'code': '200',
    'message': '',
    'trans_no': '',
    'first_due_date': '2026-08-15',
    'due_day': 15,
    'amount': loanAmount,
    'interest_rate': rate,
    'topup_fee_amount': 0,
    'fee_amount': 100,
    'installments': options(),
  });
}

/// The three contract PDFs. Each is a real (minimal) PDF whose visible text
/// says it is a mock, so an opened document can't be mistaken for a contract.
LoanDocuments mockDocuments() => LoanDocuments(
      request: _mockPdf('MOCK - loan request form'),
      receipt: _mockPdf('MOCK - receipt'),
      agreement: _mockPdf('MOCK - loan agreement'),
    );

/// Builds a minimal one-page PDF containing [caption] and returns it base64
/// encoded, matching how the API delivers these.
String _mockPdf(String caption) {
  final content = 'BT /F1 13 Tf 24 120 Td ($caption) Tj ET';
  final pdf = StringBuffer()
    ..writeln('%PDF-1.4')
    ..writeln('1 0 obj')
    ..writeln('<< /Type /Catalog /Pages 2 0 R >>')
    ..writeln('endobj')
    ..writeln('2 0 obj')
    ..writeln('<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    ..writeln('endobj')
    ..writeln('3 0 obj')
    ..writeln('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 320 200] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>')
    ..writeln('endobj')
    ..writeln('4 0 obj')
    ..writeln('<< /Length ${content.length} >>')
    ..writeln('stream')
    ..writeln(content)
    ..writeln('endstream')
    ..writeln('endobj')
    ..writeln('5 0 obj')
    ..writeln('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    ..writeln('endobj')
    ..writeln('trailer')
    ..writeln('<< /Root 1 0 R /Size 6 >>')
    ..writeln('%%EOF');
  return base64Encode(utf8.encode(pdf.toString()));
}

/// Transaction number handed back by a mock submit. The `MOCK-` prefix makes
/// it obvious in any downstream log that nothing was really filed.
String mockTransNo() =>
    'MOCK-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
