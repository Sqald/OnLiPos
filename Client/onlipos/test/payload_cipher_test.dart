import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/sale/payload_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未送信の会計データは暗号化して保存し、元に戻せる', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const plain = '{"sale":{"total_amount":1080}}';
    final stored = await PayloadCipher.encrypt(plain);
    expect(stored, isNot(contains('1080')));
    expect(await PayloadCipher.decrypt(stored), plain);
    // 暗号化前のバージョンのデータも読める
    expect(await PayloadCipher.decrypt(plain), plain);
  });
}
