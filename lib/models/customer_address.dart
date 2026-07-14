/// Models for the **get user address** API
/// (`GET /profile/address/{hash_thai_id}` — see `api_data/api1.md`).
///
/// Plain Dart (no codegen), same defensive style as `customer_detail.dart`:
/// malformed values coerce to empty strings instead of throwing.
library;

/// One postal address block (`current_address`, `registration_address`,
/// `id_card_address`, `other_address` all share this shape).
class AddressInfo {
  const AddressInfo({
    this.addressDetails = '',
    this.addressSubDistrict = '',
    this.addressDistrict = '',
    this.addressProvince = '',
    this.addressPostalCode = '',
  });

  final String addressDetails;
  final String addressSubDistrict;
  final String addressDistrict;
  final String addressProvince;
  final String addressPostalCode;

  bool get isEmpty =>
      addressDetails.isEmpty &&
      addressSubDistrict.isEmpty &&
      addressDistrict.isEmpty &&
      addressProvince.isEmpty &&
      addressPostalCode.isEmpty;

  /// Single display line: `244/98 สุชารี ไลฟ์ 2 ต.ทุ่งสองห้อง อ.หลักสี่
  /// จ.กรุงเทพมหานคร 10210` (empty parts skipped).
  String get oneLine => [
        addressDetails,
        if (addressSubDistrict.isNotEmpty) 'ต.$addressSubDistrict',
        if (addressDistrict.isNotEmpty) 'อ.$addressDistrict',
        if (addressProvince.isNotEmpty) 'จ.$addressProvince',
        addressPostalCode,
      ].where((p) => p.isNotEmpty).join(' ');

  factory AddressInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AddressInfo();
    // API values carry stray padding (e.g. "ศรีสะเกษ ") — trim everything.
    String s(dynamic v) => (v?.toString() ?? '').trim();
    return AddressInfo(
      addressDetails: s(json['address_details']),
      addressSubDistrict: s(json['address_sub_district']),
      addressDistrict: s(json['address_district']),
      addressProvince: s(json['address_province']),
      addressPostalCode: s(json['address_postal_code']),
    );
  }

  Map<String, dynamic> toJson() => {
        'address_details': addressDetails,
        'address_sub_district': addressSubDistrict,
        'address_district': addressDistrict,
        'address_province': addressProvince,
        'address_postal_code': addressPostalCode,
      };

  @override
  String toString() => 'AddressInfo(${toJson()})';
}

/// Full response of the address API: the customer's four registered
/// addresses plus the data snapshot date.
class CustomerAddressBook {
  const CustomerAddressBook({
    this.currentAddress = const AddressInfo(),
    this.registrationAddress = const AddressInfo(),
    this.idCardAddress = const AddressInfo(),
    this.otherAddress = const AddressInfo(),
    this.dataDate,
  });

  final AddressInfo currentAddress;
  final AddressInfo registrationAddress;
  final AddressInfo idCardAddress;
  final AddressInfo otherAddress;
  final DateTime? dataDate;

  factory CustomerAddressBook.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? block(dynamic v) =>
        v is Map<String, dynamic> ? v : null;
    return CustomerAddressBook(
      currentAddress: AddressInfo.fromJson(block(json['current_address'])),
      registrationAddress:
          AddressInfo.fromJson(block(json['registration_address'])),
      idCardAddress: AddressInfo.fromJson(block(json['id_card_address'])),
      otherAddress: AddressInfo.fromJson(block(json['other_address'])),
      dataDate: DateTime.tryParse('${json['data_date'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'current_address': currentAddress.toJson(),
        'registration_address': registrationAddress.toJson(),
        'id_card_address': idCardAddress.toJson(),
        'other_address': otherAddress.toJson(),
        'data_date': dataDate?.toIso8601String(),
      };

  @override
  String toString() => 'CustomerAddressBook(${toJson()})';
}
