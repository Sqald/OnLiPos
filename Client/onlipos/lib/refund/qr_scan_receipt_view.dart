import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// レシートのQRコードを読み取り、レシート番号を返す画面
class QrScanReceiptView extends StatefulWidget {
  const QrScanReceiptView({super.key});

  @override
  State<QrScanReceiptView> createState() => _QrScanReceiptViewState();
}

class _QrScanReceiptViewState extends State<QrScanReceiptView> {
  MobileScannerController? _controller;
  bool _hasScanned = false;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // QRコードを検出したら最初の1件のみを読み取り値として画面を閉じる
  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _hasScanned = true;
        Navigator.of(context).pop(raw.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMobile) {
      // デスクトップなどモバイル非対応環境では説明のみ表示
      return Scaffold(
        appBar: const AppHeader('レシートのQRを読み取る'),
        body: EmptyState(
          icon: Icons.qr_code_scanner,
          title: 'この端末ではカメラでの読み取りを使えません',
          message: 'レシート番号を入力してください。',
          action: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('戻る'),
          ),
        ),
      );
    }

    _controller ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    return Scaffold(
      appBar: AppHeader(
        'レシートのQRを読み取る',
        subtitle: 'レシートのQRコードをカメラに映してください',
        actions: [
          IconButton(
            tooltip: 'ライト',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(controller: _controller!, onDetect: _onDetect),
    );
  }
}
