import 'package:flutter_test/flutter_test.dart';
import 'package:onlipos/sale/send_to_api.dart';

void main() {
  group('SentToApi.newRequestId', () {
    test('UUID v4 形式で、サーバーが受け付ける形式に合う', () {
      final id = SentToApi.newRequestId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('呼び出しごとに異なる値になる', () {
      final ids = List.generate(100, (_) => SentToApi.newRequestId()).toSet();
      expect(ids.length, 100);
    });
  });

  group('SentToApi.isPermanentFailure', () {
    test('409・422 は再送しても成功しない失敗', () {
      expect(SentToApi.isPermanentFailure(409), isTrue);
      expect(SentToApi.isPermanentFailure(422), isTrue);
    });

    test('認証・権限・タイムアウト・レート制限・5xx は再送対象', () {
      for (final status in [401, 403, 408, 429, 500, 503]) {
        expect(
          SentToApi.isPermanentFailure(status),
          isFalse,
          reason: '$status',
        );
      }
    });
  });
}
