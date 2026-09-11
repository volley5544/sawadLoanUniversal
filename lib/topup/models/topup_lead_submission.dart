/// Body for the **lead** fallback — `POST {lead base}/ssw_service_api/api/
/// leads/lh-save`.
///
/// Filed instead of a top-up when the amount screen decides the request cannot
/// be self-served ([TopupOutcome.lead]): a land or house loan type, a
/// `can_topup` refusal, or a payout above the contract's
/// `max_transfer_amount`. Somebody calls the customer back.
///
/// The whole contract is forwarded, sub-objects included, which is why this
/// reads [LoanContract.rawJson] rather than rebuilding them from typed fields:
/// this service is not ours and re-serialising would drop keys we don't model.
library;

import '../../models/customer_detail.dart';
import 'topup_flow.dart';

class TopupLeadSubmission {
  const TopupLeadSubmission._(this.fields);

  final Map<String, dynamic> fields;

  factory TopupLeadSubmission.fromFlow(TopupFlow flow) {
    final contract = flow.contract;
    if (contract == null) {
      throw StateError('Top-up flow has no contract: cannot build lead');
    }
    final raw = contract.rawJson;
    final customer = flow.customer ?? const CustomerDetail();

    Object? sub(String key) => raw[key];

    return TopupLeadSubmission._({
      'thai_id': customer.thaiId,
      'hash_thai_id': flow.hashThaiId,
      'contract_details': sub('contract_details') ?? const {},
      'car_details': sub('car_details') ?? const {},
      'payment_details': sub('payment_details') ?? const {},
      'topup_detail': sub('topup_detail') ?? const {},
      'barcode_details': sub('barcode_details') ?? const {},
      'insurances': sub('insurances') ?? const [],
      'data_date': contract.dataDate,
      'contract_name': contract.contractName,
      'db_name': contract.dbName,
      'contract_no': contract.contractNo,
      'contract_no_blinding': contract.contractNo,
      'contract_bank_type': contract.contractBankType,
      'contract_bank_account': contract.contractBankAccount,
      'contract_bank_brandname': contract.contractBankBrandname,
      'contract_date': contract.contractDate,
      'contract_close_date': contract.contractCloseDate,
      'transno': contract.transNo,
      'request_topup_amount': '${flow.requestedAmount}',
      'request_date': contract.requestDate,
      'request_status': contract.requestStatusCode,
      'loan_amount': '${flow.calculatedAmount}',
      'branch_code': contract.branchCode,
      'branch_name': contract.branchName,
      'title_id': customer.title,
      'title_name': customer.title,
      'first_name': customer.firstName,
      'last_name': customer.lastName,
      'phone_number': customer.phoneNumber,
      'birth_date': customer.dob?.toIso8601String().split('T').first ?? '',
      'age': '',
      'email': customer.email,
      'contract_thai_id': customer.thaiId,
      // PDPA is answered on the conclusion screen, which a lead never reaches.
      // Sending 'Y' here would record a consent that was never given, so the
      // flag goes out empty and the lead service can ask for it properly.
      'pdpa_flg': '',
      'pdpa_date': '',
      'utm_source': flow.source,
      'utm_medium': '',
      'utm_campaign': flow.referId,
    });
  }
}
