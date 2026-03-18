import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

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
        appBar: AppBar(
          title: const Text('レシートQRを読み取る'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'QRコード読み取りはモバイル端末でのみ利用できます。\nレシート番号を手入力してください。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('戻る'),
                ),
              ],
            ),
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
      appBar: AppBar(
        title: const Text('レシートQRを読み取る'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller!,
        onDetect: _onDetect,
      ),
    );
  }
}
