/// Model representing a customer's detail returned by the API.
///
/// Use [CustomerDetail.fromJson] to parse API responses and [toJson] to
/// serialize back. The model is plain Dart (no codegen) so it works
/// everywhere in the app without `build_runner`.
class CustomerDetail {
  final bool isExistingCustomer;
  final String thaiId;
  final String title;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final DateTime? dob;
  final String email;
  final String addressDetails;
  final String addressSubDistrict;
  final String addressDistinct;
  final String addressProvince;
  final String addressPostalCode;
  final String lineId;
  final String uid;
  final String fcmToken;
  final String latitude;
  final String longitude;
  final bool? consent;
  final DateTime? consentUpdatedAt;
  final String isAgent;
  final String agentCode;

  const CustomerDetail({
    this.isExistingCustomer = false,
    this.thaiId = '',
    this.title = '',
    this.firstName = '',
    this.lastName = '',
    this.phoneNumber = '',
    this.dob,
    this.email = '',
    this.addressDetails = '',
    this.addressSubDistrict = '',
    this.addressDistinct = '',
    this.addressProvince = '',
    this.addressPostalCode = '',
    this.lineId = '',
    this.uid = '',
    this.fcmToken = '',
    this.latitude = '',
    this.longitude = '',
    this.consent,
    this.consentUpdatedAt,
    this.isAgent = '',
    this.agentCode = '',
  });

  /// First and last name with surrounding whitespace removed.
  String get fullName => '${firstName.trim()} ${lastName.trim()}'.trim();

  /// Whether this customer is flagged as an agent (`is_agent == "Y"`).
  bool get isAgentFlag => isAgent.trim().toUpperCase() == 'Y';

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    return CustomerDetail(
      isExistingCustomer: _asBool(json['is_existing_customer']),
      thaiId: _asString(json['thai_id']),
      title: _asString(json['title']),
      firstName: _asString(json['first_name']),
      lastName: _asString(json['last_name']),
      phoneNumber: _asString(json['phone_number']),
      dob: _asDate(json['dob']),
      email: _asString(json['email']),
      addressDetails: _asString(json['address_details']),
      addressSubDistrict: _asString(json['address_sub_district']),
      addressDistinct: _asString(json['address_distinct']),
      addressProvince: _asString(json['address_province']),
      addressPostalCode: _asString(json['address_postal_code']),
      lineId: _asString(json['line_id']),
      uid: _asString(json['uid']),
      fcmToken: _asString(json['fcm_token']),
      latitude: _asString(json['latitude']),
      longitude: _asString(json['longitude']),
      consent: json['consent'] == null ? null : _asBool(json['consent']),
      consentUpdatedAt: _asDate(json['consent_updated_at']),
      isAgent: _asString(json['is_agent']),
      agentCode: _asString(json['agent_code']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_existing_customer': isExistingCustomer,
      'thai_id': thaiId,
      'title': title,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'dob': dob?.toUtc().toIso8601String(),
      'email': email,
      'address_details': addressDetails,
      'address_sub_district': addressSubDistrict,
      'address_distinct': addressDistinct,
      'address_province': addressProvince,
      'address_postal_code': addressPostalCode,
      'line_id': lineId,
      'uid': uid,
      'fcm_token': fcmToken,
      'latitude': latitude,
      'longitude': longitude,
      'consent': consent,
      'consent_updated_at': consentUpdatedAt?.toIso8601String(),
      'is_agent': isAgent,
      'agent_code': agentCode,
    };
  }

  CustomerDetail copyWith({
    bool? isExistingCustomer,
    String? thaiId,
    String? title,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    DateTime? dob,
    String? email,
    String? addressDetails,
    String? addressSubDistrict,
    String? addressDistinct,
    String? addressProvince,
    String? addressPostalCode,
    String? lineId,
    String? uid,
    String? fcmToken,
    String? latitude,
    String? longitude,
    bool? consent,
    DateTime? consentUpdatedAt,
    String? isAgent,
    String? agentCode,
  }) {
    return CustomerDetail(
      isExistingCustomer: isExistingCustomer ?? this.isExistingCustomer,
      thaiId: thaiId ?? this.thaiId,
      title: title ?? this.title,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dob: dob ?? this.dob,
      email: email ?? this.email,
      addressDetails: addressDetails ?? this.addressDetails,
      addressSubDistrict: addressSubDistrict ?? this.addressSubDistrict,
      addressDistinct: addressDistinct ?? this.addressDistinct,
      addressProvince: addressProvince ?? this.addressProvince,
      addressPostalCode: addressPostalCode ?? this.addressPostalCode,
      lineId: lineId ?? this.lineId,
      uid: uid ?? this.uid,
      fcmToken: fcmToken ?? this.fcmToken,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      consent: consent ?? this.consent,
      consentUpdatedAt: consentUpdatedAt ?? this.consentUpdatedAt,
      isAgent: isAgent ?? this.isAgent,
      agentCode: agentCode ?? this.agentCode,
    );
  }

  @override
  String toString() => 'CustomerDetail(${toJson()})';

  // --- Safe coercion helpers -------------------------------------------------

  static String _asString(dynamic value) => value?.toString() ?? '';

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'y' || v == 'yes';
    }
    return false;
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
