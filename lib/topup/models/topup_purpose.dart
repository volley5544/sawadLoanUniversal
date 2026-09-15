/// The add-on product a top-up is being raised for, when the customer picked
/// one.
///
/// ⚠ There is no วัตถุประสงค์ screen (removed 2026-09-11) — the contract card
/// already settles this. Tapping **เติมวงเงิน** leaves it null, which is a
/// plain top-up at [kTopupOtherProductCode]; tapping a
/// **สิทธิพิเศษเฉพาะคุณ** tile carries that product's code and price onto the
/// flow. So this is a value the card constructs, not a list anything renders.
library;

/// The source's "อื่นๆ" row in its วัตถุประสงค์ list — a **UI** value, for a
/// screen this build removed on 2026-09-11.
///
/// ⚠ **Never send this to `POST /topup`.** A plain top-up's `product_code` is
/// the **empty string**; the source sends
/// `products == ProductsStruct() ? '' : products.productCode`. Sending
/// `OTR001` earned `501 / ข้อมูลบางส่วนผิดพลาดไม่สามารถสร้างใบคำขอได้` on a live
/// submit (2026-09-15). It survives only as the marker [TopupPurpose.isOther]
/// tests, which decides whether the amount field is editable.
const String kTopupOtherProductCode = 'OTR001';

/// The product a top-up is raised for.
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

  /// Whether this is the plain top-up rather than a real add-on product.
  ///
  /// The amount screen lets the customer edit the figure only in that case —
  /// a named product is priced by the product, so its tile fixes the amount.
  bool get isOther => productCode == kTopupOtherProductCode;
}
