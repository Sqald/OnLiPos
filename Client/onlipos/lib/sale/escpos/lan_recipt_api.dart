import 'dart:io';
import 'package:charset_converter/charset_converter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ReceiptPrinter {
  final String ipAddress;
  final int port;

  ReceiptPrinter({this.ipAddress = '192.168.192.168', this.port = 9100});

  /// キャッシュドロアを開く。プロビジョニングの drawer_kick_command を送信する。
  /// レジ金チェック・精算・開設画面表示時に呼ぶ。
  static Future<void> openDrawer() async {
    const storage = FlutterSecureStorage();
    final String? savedIp = await storage.read(key: 'PrinterIP');
    final String? kickCommand = await storage.read(key: 'DrawerKickCommand');
    if (savedIp == null || savedIp.isEmpty) return;

    final String cmd = kickCommand ?? '27,112,0,50,250';
    final List<int> bytes = cmd.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();

    Socket? socket;
    try {
      socket = await Socket.connect(savedIp, 9100, timeout: const Duration(seconds: 3));
      socket.add(bytes);
      await socket.flush();
    } catch (e) {
      print('Drawer open error: $e');
    } finally {
      socket?.destroy();
    }
  }

  Future<void> printReceipt({
    required String receiptNumber,
    required int totalAmount,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> paymentMethods,
    required int change,
    required int tenderedCash,
  }) async {
    const storage = FlutterSecureStorage();
    
    String targetIp = ipAddress;
    String storeName = "お会計";
    
    String? savedIp = await storage.read(key: 'PrinterIP');
    String? savedName = await storage.read(key: 'StoreName');
    if (savedIp != null && savedIp.isNotEmpty) targetIp = savedIp;
    if (savedName != null && savedName.isNotEmpty) storeName = savedName;

    if (tenderedCash > 0) {
      await ReceiptPrinter.openDrawer();
    }

    Socket? socket;
    try {
      socket = await Socket.connect(targetIp, port, timeout: const Duration(seconds: 3));
      final List<int> buffer = [];

      // Initialize (ESC @)
      buffer.addAll([0x1B, 0x40]);

      // 漢字モード設定 (Shift_JIS)
      buffer.addAll([0x1B, 0x52, 0x08]);
      buffer.addAll([0x1B, 0x74, 0x01]);
      buffer.addAll([0x1C, 0x43, 0x01]);

      Future<void> addLine(String text, {int align = 0, bool bold = false, int size = 0}) async {
        buffer.addAll([0x1B, 0x61, align]);

        int n = 0;
        if (bold) n |= 0x08;
        if (size == 1 || size == 3) n |= 0x10;
        if (size == 2 || size == 3) n |= 0x20;
        buffer.addAll([0x1B, 0x21, n]);
        
        try {
          if (text.isNotEmpty) {
            final encoded = await CharsetConverter.encode("Shift_JIS", text);
            buffer.addAll(encoded);
          }
        } catch (e) {
          buffer.addAll(text.codeUnits.map((e) => e > 255 ? 63 : e).toList());
        }
        
        buffer.addAll([0x0A]);
        buffer.addAll([0x1B, 0x21, 0x00]);
      }

      // --- Receipt Content ---
      await addLine(storeName, align: 1, size: 3, bold: true);
      await addLine("");
      await addLine("領 収 書", align: 1, size: 1);
      await addLine("--------------------------------", align: 1);
      
      await addLine("日時: ${DateTime.now().toString().substring(0, 19)}");
      await addLine("No: $receiptNumber");
      await addLine("--------------------------------", align: 1);
      await addLine("");

      for (var item in details) {
        final name = item['product_name']?.toString() ?? '';
        final code = item['product_code']?.toString() ?? '';
        final qty = item['quantity'] is int ? item['quantity'] as int : (item['quantity'] as num).toInt();
        final price = item['unit_price'] is int ? item['unit_price'] as int : (item['unit_price'] as num).toInt();
        final sub = item['subtotal'] is int ? item['subtotal'] as int : (item['subtotal'] as num).toInt();

        final lineTitle = code.isNotEmpty ? '$code  $name' : name;
        await addLine(lineTitle, align: 0, bold: true);
        await addLine("  $qty x $price  = $sub", align: 2);
      }
      
      await addLine("");
      await addLine("--------------------------------", align: 1);
      await addLine("合計  ¥$totalAmount", align: 2, size: 3, bold: true);
      await addLine("");

      for (var p in paymentMethods) {
        await addLine("${p['method']}: ${p['amount']}", align: 2);
      }

      if (tenderedCash > 0) {
        await addLine("お預かり: $tenderedCash", align: 2);
        await addLine("お釣り: $change", align: 2, size: 1, bold: true);
      }

      await addLine("");
      await addLine("--------------------------------", align: 1);
      await addLine("ご利用ありがとうございます", align: 1);
      
      // --- レシート識別用 QRコード (長い文字列対応) ---
      
      buffer.addAll([0x0A, 0x0A]); // 前に余白を開ける
      buffer.addAll([0x1B, 0x61, 0x01]); // 中央揃え

      // QRコードに埋め込むデータ
      List<int> qrData = receiptNumber.codeUnits;
      
      // データ長 + 3バイト (コマンド仕様)
      int dataLen = qrData.length + 3;
      int pL = dataLen % 256;
      int pH = dataLen ~/ 256;

      // 1. QRコードのモデル設定 (Model 2)
      buffer.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

      // 2. モジュールサイズ設定 (QRコードの大きさ。4ドット=適度な大きさ)
      buffer.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04]);

      // 3. エラー訂正レベル設定 (48 = レベルL: 復元能力7%)
      buffer.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);

      // 4. QRコードのデータをプリンタのメモリに格納
      buffer.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
      buffer.addAll(qrData);

      // 5. メモリに格納したQRコードを印字
      buffer.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
      
      buffer.addAll([0x1B, 0x61, 0x00]); // 一旦左揃えにリセット
      // ----------------------------------------------------

      // QRコードの下に人間が読めるレシート番号（HRIの代わり）をテキストで印字
      await addLine(receiptNumber, align: 1); // 中央揃えでテキスト印字

      // カット前に十分な余白を開ける (カッターの刃まで届かせるための改行×6)
      buffer.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]);

      // Cut Paper (GS V m)
      buffer.addAll([0x1D, 0x56, 0x00]);
      // Send Data
      socket.add(buffer);
      await socket.flush();
      
    } catch (e) {
      print("Printer Error: $e");
    } finally {
      socket?.destroy();
    }
  }

  /// 返品レシートを印刷する。元の会計が現金の場合は openDrawer を true にしキャッシュドロアを開く。
  static Future<void> printRefundReceipt({
    required String refundReceiptNumber,
    required int totalRefundAmount,
    required List<Map<String, dynamic>> details,
    required List<Map<String, dynamic>> paymentMethods,
    required bool openDrawer,
  }) async {
    if (openDrawer) {
      await ReceiptPrinter.openDrawer();
    }

    const storage = FlutterSecureStorage();
    String targetIp = '192.168.192.168';
    String storeName = "返品";
    final String? savedIp = await storage.read(key: 'PrinterIP');
    final String? savedName = await storage.read(key: 'StoreName');
    if (savedIp != null && savedIp.isNotEmpty) targetIp = savedIp;
    if (savedName != null && savedName.isNotEmpty) storeName = savedName;

    Socket? socket;
    try {
      socket = await Socket.connect(targetIp, 9100, timeout: const Duration(seconds: 3));
      final List<int> buffer = [];

      buffer.addAll([0x1B, 0x40]);
      buffer.addAll([0x1B, 0x52, 0x08]);
      buffer.addAll([0x1B, 0x74, 0x01]);
      buffer.addAll([0x1C, 0x43, 0x01]);

      Future<void> addLine(String text, {int align = 0, bool bold = false, int size = 0}) async {
        buffer.addAll([0x1B, 0x61, align]);
        int n = 0;
        if (bold) n |= 0x08;
        if (size == 1 || size == 3) n |= 0x10;
        if (size == 2 || size == 3) n |= 0x20;
        buffer.addAll([0x1B, 0x21, n]);
        try {
          if (text.isNotEmpty) {
            final encoded = await CharsetConverter.encode("Shift_JIS", text);
            buffer.addAll(encoded);
          }
        } catch (e) {
          buffer.addAll(text.codeUnits.map((e) => e > 255 ? 63 : e).toList());
        }
        buffer.addAll([0x0A]);
        buffer.addAll([0x1B, 0x21, 0x00]);
      }

      await addLine(storeName, align: 1, size: 3, bold: true);
      await addLine("");
      await addLine("返品レシート", align: 1, size: 1);
      await addLine("--------------------------------", align: 1);
      await addLine("日時: ${DateTime.now().toString().substring(0, 19)}");
      await addLine("No: $refundReceiptNumber");
      await addLine("--------------------------------", align: 1);
      await addLine("");

      for (var item in details) {
        final name = item['product_name']?.toString() ?? '';
        final code = item['product_code']?.toString() ?? '';
        final qty = item['quantity'] is int ? item['quantity'] as int : (item['quantity'] as num).toInt();
        final price = item['unit_price'] is int ? item['unit_price'] as int : (item['unit_price'] as num).toInt();
        final sub = item['subtotal'] is int ? item['subtotal'] as int : (item['subtotal'] as num).toInt();
        final lineTitle = code.isNotEmpty ? '$code  $name' : name;
        await addLine(lineTitle, align: 0, bold: true);
        await addLine("  $qty x $price  = $sub", align: 2);
      }

      await addLine("");
      await addLine("--------------------------------", align: 1);
      await addLine("返金合計  ¥$totalRefundAmount", align: 2, size: 3, bold: true);
      await addLine("");
      if (paymentMethods.isNotEmpty) {
        await addLine("元会計の支払方法", align: 0, bold: true);
        for (final pm in paymentMethods) {
          final method = pm['method']?.toString() ?? '';
          final amount = pm['amount'] is int ? pm['amount'] as int : (pm['amount'] as num?)?.toInt() ?? 0;
          await addLine("  $method: ¥$amount", align: 2);
        }
        await addLine("");
      }
      await addLine("--------------------------------", align: 1);
      await addLine("ご利用ありがとうございます", align: 1);
      buffer.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]);
      buffer.addAll([0x1D, 0x56, 0x00]);
      socket.add(buffer);
      await socket.flush();
    } catch (e) {
      print("Refund Printer Error: $e");
    } finally {
      socket?.destroy();
    }
  }
}