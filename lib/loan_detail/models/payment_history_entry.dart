/// One row of `POST /payment/history_new` — a payment the customer has already
/// made against a contract, for the **ประวัติการชำระ** tab of the loan detail
/// screen.
library;

import '../../p_loan/application/models/json_coerce.dart';

class PaymentHistoryEntry {
  const PaymentHistoryEntry({
    this.date = '',
    this.paidAmount = 0,
    this.paymentChannelCode = '',
    this.paymentChannelName = '',
  });

  /// `date` — as sent, **`dd-MM-yyyy HH:mm`** on the endpoint both reference
  /// clients read. Kept raw; [paidOn] and [paidAtTime] split it.
  final String date;
  final double paidAmount;
  final String paymentChannelCode;
  final String paymentChannelName;

  factory PaymentHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PaymentHistoryEntry(
        date: asString(json['date']),
        paidAmount: asDouble(json['paid_amount']),
        paymentChannelCode: asString(json['payment_channel_code']),
        paymentChannelName: asString(json['payment_channel_name']),
      );

  /// The date half of [date] as a `DateTime`, or null when it can't be read.
  ///
  /// ⚠ **The day comes first**, not the year: the source builds an ISO string
  /// by reversing the three parts (`split[2]-split[1]-split[0]`), which only
  /// yields a parseable date if the wire format is `dd-MM-yyyy`. A four-digit
  /// leading segment is treated as ISO instead, so a backend that switches to
  /// `yyyy-MM-dd` renders correctly rather than silently reading the day as a
  /// year.
  DateTime? get paidOn {
    final datePart = date.trim().split(' ').first;
    if (datePart.isEmpty) return null;
    final parts = datePart.split('-');
    if (parts.length != 3) return DateTime.tryParse(datePart);
    if (parts.first.length == 4) return DateTime.tryParse(datePart);
    return DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
  }

  /// The `HH:mm` half of [date], or `''` when it carries no time.
  String get paidAtTime {
    final pieces = date.trim().split(' ');
    return pieces.length > 1 ? pieces[1] : '';
  }
}
