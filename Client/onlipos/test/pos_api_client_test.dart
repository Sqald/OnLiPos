import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onlipos/api/pos_api_client.dart';

void main() {
  group('PosApiClient.normalizeBaseUrl', () {
    test('末尾のスラッシュを取り除く', () {
      expect(
        PosApiClient.normalizeBaseUrl('https://example.com/'),
        'https://example.com',
      );
    });

    test('末尾にスラッシュがなければそのまま', () {
      expect(
        PosApiClient.normalizeBaseUrl('https://example.com'),
        'https://example.com',
      );
    });
  });

  group('PosApiClient.parseJson', () {
    test('JSONオブジェクトはそのまま返す', () {
      final result = PosApiClient.parseJson(
        http.Response('{"success": true, "id": 1}', 200),
      );
      expect(result, {'success': true, 'id': 1});
    });

    test('JSON以外の応答はステータスコード付きのエラーにする', () {
      final result = PosApiClient.parseJson(
        http.Response('<html>Bad Gateway</html>', 502),
      );
      expect(result['success'], false);
      expect(result['message'], 'サーバーエラー: 502');
    });

    test('配列のJSONはエラーにする', () {
      final result = PosApiClient.parseJson(http.Response('[1, 2]', 200));
      expect(result['success'], false);
    });
  });
}
