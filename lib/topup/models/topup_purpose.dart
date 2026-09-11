/// The "what is this top-up for?" options shown on step 2.
///
/// They are **not** fetched: they are the add-on products the contract itself
/// offers (`topup_detail.products` on `GET /loan/list`), plus a synthesised
/// "อื่นๆ" entry standing for the plain top-up at the contract's default limit.
library;

import '../../p_loan/application/models/loan_contract.dart';

/// Product code of the synthesised catch-all option.
const String kTopupOtherProductCode = 'OTR001';

/// One option on the purpose screen.
class TopupPurpose {
  const TopupPurpose({
    required this.productCode,
    required this.productName,
    required this.productDescription,
    required this.productPrice,
  });

  /// `product_code` sent with the submit payload. [kTopupOtherProductCode] for
  /// the catch-all.
  final String productCode;
  final String productName;
  final String productDescription;

  /// The amount this purpose asks for, in baht.
  final int productPrice;

  /// Whether this is the synthesised "อื่นๆ" option rather than a real add-on
  /// product. The amount screen lets the customer edit the figure only for
  /// this one — a named product is priced by the product.
  bool get isOther => productCode == kTopupOtherProductCode;

  /// The options for [contract], in the order the screen lists them.
  ///
  /// The source built this by **appending to the contract's own list**, which
  /// grew that list by one "อื่นๆ" every time the screen was opened. Building a
  /// fresh list avoids that.
  static List<TopupPurpose> forContract(LoanContract contract) {
    final detail = contract.topupDetail;
    return [
      for (final p in detail.products)
        if (!p.isEmpty)
          TopupPurpose(
            productCode: p.productCode,
            productName: p.productName,
            productDescription: p.productDescription,
            productPrice: p.productPrice,
          ),
      TopupPurpose(
        productCode: kTopupOtherProductCode,
        productName: 'อื่นๆ',
        productDescription: '',
        productPrice: detail.defaultTopupAmount,
      ),
    ];
  }
}
