import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/app_config.dart';

void main() {
  test('AppConfig memvalidasi environment aktif', () {
    expect(AppConfig.apiUrl, isNotEmpty);
    expect(AppConfig.apiUrl.endsWith('/'), isFalse);
    expect(() => AppConfig.validate(), returnsNormally);
  });
}
