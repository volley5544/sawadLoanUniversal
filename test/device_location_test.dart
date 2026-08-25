import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/device_location.dart';

void main() {
  group('GeoPosition formatting', () {
    test('renders seven decimals, matching the API sample values', () {
      // The /ploan sample sends "13.8890019" / "100.5755956". A stable string
      // shape matters more than the precision — the payload's fields are
      // strings, and a bare double.toString() varies in digit count.
      const position = GeoPosition(latitude: 13.8890019, longitude: 100.5755956);
      expect(position.latitudeString, '13.8890019');
      expect(position.longitudeString, '100.5755956');
    });

    test('pads a short value rather than emitting a ragged one', () {
      const position = GeoPosition(latitude: 13.5, longitude: 100.0);
      expect(position.latitudeString, '13.5000000');
      expect(position.longitudeString, '100.0000000');
    });

    test('keeps the sign on southern/western coordinates', () {
      // Thailand is neither, but the payload field is a plain string and a
      // dropped minus sign would silently relocate an application hemispheres
      // away rather than failing.
      const position = GeoPosition(latitude: -33.8688197, longitude: -70.1234567);
      expect(position.latitudeString, startsWith('-33.'));
      expect(position.longitudeString, startsWith('-70.'));
    });
  });

  group('off-web stub', () {
    test('reports unsupported and returns null instead of throwing', () async {
      // Under `flutter test` there is no navigator.geolocation. The contract is
      // that this is not an error: the caller leaves the coordinates empty and
      // the application still submits.
      expect(DeviceLocation.isSupported, isFalse);
      expect(await DeviceLocation.current(), isNull);
    });
  });
}
