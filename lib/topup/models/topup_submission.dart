/// Body for `POST /topup` — the filed top-up request.
///
/// Key names mirror the API exactly, including `topup_argeement_file`: the
/// misspelling is the real wire key, not a typo on our side.
///
/// Kept as a mapper rather than built inline on the conclusion screen so the
/// payload can be tested without a widget, and so every "why is this field
/// blank?" question has one place to answer it ([unresolvedFields]).
library;

import '../../p_loan/application/models/loan_documents.dart';
import 'topup_flow.dart';
import 'topup_photo.dart';
import 'topup_purpose.dart';

class TopupSubmission {
  const TopupSubmission._(this.fields, this.unresolvedFields);

  /// The JSON body, ready to post.
  final Map<String, dynamic> fields;

  /// Fields that went out empty and are **not** empty by design.
  ///
  /// Appended to a refusal message, because "HTTP 400" against 37 fields is
  /// unactionable on a device.
  final List<String> unresolvedFields;

  /// Fields that are legitimately blank and so are never reported.
  ///
  /// `latitude`/`longitude` are captured on the conclusion screen without
  /// being awaited — a denied permission or a cold GPS must not stop an
  /// application being filed — and `transno` is always empty on a new request
  /// (the server assigns it).
  static const Set<String> acceptedBlank = {
    'transno',
    'latitude',
    'longitude',
  };

  /// Builds the body for [flow].
  ///
  /// Throws [StateError] only when the flow is missing something no payload
  /// could be built without; everything softer is reported instead.
  factory TopupSubmission.fromFlow(TopupFlow flow) {
    final contract = flow.contract;
    final detail = flow.amountDetail;
    final installment = flow.installment;
    final pdfRequest = flow.pdfRequest;
    if (contract == null ||
        detail == null ||
        installment == null ||
        pdfRequest == null) {
      throw StateError('Top-up flow incomplete: cannot build submit payload');
    }

    /// Photos travel as data URLs, the way the source sent them.
    String image(TopupPhoto slot) {
      final b64 = flow.base64OfPhoto(slot);
      return b64.isEmpty ? '' : 'data:image/jpeg;base64,$b64';
    }

    final docs = flow.documents ?? const LoanDocuments();

    final fields = <String, dynamic>{
      'transno': '',
      'db_name': detail.dbName,
      'hash_thai_id': flow.hashThaiId,
      'contract_no': detail.contractNo,
      'life_insure_amt': detail.lifeInsureAmt,
      // Real answers, not the hardcoded 'Y'/'Y' the source sent. `N` is a
      // legitimate reply to the marketing question, so neither is ever
      // reported as unresolved.
      'marketing_consent': flow.marketingConsent ? 'Y' : 'N',
      'sensitive_consent': flow.sensitiveConsent ? 'Y' : 'N',
      'latitude': flow.latitude,
      'longitude': flow.longitude,
      'loan_amount': flow.calculatedAmount,
      'topup_fee': flow.plan?.topupFeeAmount ?? detail.feeAmount,
      'fee_amount': flow.feeAmount,
      'transfer_amount': flow.payoutAmount,
      'interest_rate': flow.plan?.interestRate ?? detail.interestRate,
      'interest_amount': installment.intAmt,
      'total_amount': installment.totalAmt,
      'credit_limit': detail.contractDetails.creditLimit,
      'term_period': installment.tenor,
      'regular_period': installment.regularPeriodAmt,
      'last_period': installment.lastPeriodAmt,
      'last_period_promo': installment.lastPeriodPromo,
      'act_image': image(TopupPhoto.taxDisc),
      'property_image': image(TopupPhoto.fullVehicle),
      'car_image_front': image(TopupPhoto.carFront),
      'car_image_back': image(TopupPhoto.carBack),
      'car_image_left': image(TopupPhoto.carLeft),
      'car_image_right': image(TopupPhoto.carRight),
      'car_image_mile': image(TopupPhoto.carMile),
      'customer_image_2': image(TopupPhoto.idCard),
      'customer_image_3': image(TopupPhoto.selfieWithIdCard),
      'topup_request_file': docs.request,
      'topup_receipt_file': docs.receipt,
      // Misspelled on the wire — matches the API, not our typo.
      'topup_argeement_file': docs.agreement,
      'save_pdf': pdfRequest.toJson(),
      'source': flow.source,
      'refer_id': flow.referId,
      'product_code': flow.purpose?.productCode ?? kTopupOtherProductCode,
    };

    // A photo slot this loan type never asks for is blank by design; only the
    // ones the flow required are worth reporting.
    final expected = <String>{
      for (final slot in flow.requiredPhotos) slot.payloadKey,
      for (final slot in TopupPhoto.identity) slot.payloadKey,
      'topup_request_file',
      'topup_receipt_file',
      'topup_argeement_file',
      'db_name',
      'contract_no',
      'hash_thai_id',
    };

    final unresolved = <String>[
      for (final key in expected)
        if (!acceptedBlank.contains(key) &&
            '${fields[key] ?? ''}'.trim().isEmpty)
          key,
    ]..sort();

    return TopupSubmission._(fields, List.unmodifiable(unresolved));
  }
}
