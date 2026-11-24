/// 未送信の会計データ（端末のSQLiteに保存）の暗号化。
/// 鍵は SecureStorage（OSの安全な保管領域）に置き、DBファイルだけを持ち出されても読めないようにする。
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PayloadCipher {
  static const _prefix = 'enc1:';
  static const _keyName = 'OfflinePayloadKey';
  static const _storage = FlutterSecureStorage();
  static final _algorithm = AesGcm.with256bits();
  static SecretKey? _key;

  static Future<SecretKey> _secretKey() async {
    if (_key != null) return _key!;
    final stored = await _storage.read(key: _keyName);
    if (stored != null) return _key = SecretKey(base64Decode(stored));

    final key = await _algorithm.newSecretKey();
    await _storage.write(
      key: _keyName,
      value: base64Encode(await key.extractBytes()),
    );
    return _key = key;
  }

  static Future<String> encrypt(String plain) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plain),
      secretKey: await _secretKey(),
    );
    return _prefix + base64Encode(box.concatenation());
  }

  /// 暗号化前のバージョンで保存されたデータはそのまま返す
  static Future<String> decrypt(String stored) async {
    if (!stored.startsWith(_prefix)) return stored;
    final box = SecretBox.fromConcatenation(
      base64Decode(stored.substring(_prefix.length)),
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    return utf8.decode(
      await _algorithm.decrypt(box, secretKey: await _secretKey()),
    );
  }
}
