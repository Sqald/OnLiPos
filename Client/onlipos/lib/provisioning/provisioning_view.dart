import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../product/master_sync_api.dart';
import '../login/login_top_view.dart';
import '../sale/send_to_api.dart';
import 'provisioning_api.dart';

class ProvisioningPage extends StatefulWidget {
  final VoidCallback? onFinished;

  const ProvisioningPage({super.key, this.onFinished});

  @override
  State<ProvisioningPage> createState() => _ProvisioningPageState();
}

class _ProvisioningPageState extends State<ProvisioningPage> {
  String _statusMessage = '準備中...';
  int _processedCount = 0;
  bool _hasError = false;
  bool _isFinished = false;
  final Map<String, String> _syncedSettings = {};

  @override
  void initState() {
    super.initState();
    _exec();
  }

  Future<void> _exec() async {
    try {
      const storage = FlutterSecureStorage();
      final String? baseUrl = await storage.read(key: 'AccessUrl');
      final String? authToken = await storage.read(key: 'LoginToken');

      // 接続情報が取得できない場合はエラーとして処理
      if (baseUrl == null || baseUrl.isEmpty) {
        throw Exception('接続先URLが設定されていません');
      }
      if (authToken == null || authToken.isEmpty) {
        // トークンがない場合は同期不要（またはエラー）と判断し、次の画面へ
        // ここではエラーにせず、そのままログイン画面に進む
        setState(() => _statusMessage = '認証情報がありません。');
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // プロビジョニング（端末設定）の取得
        setState(() => _statusMessage = '端末設定を取得中...');
        try {
          final provisioningData = await ProvisioningApi.getProvisioning();
          if (provisioningData['hardware_settings'] != null) {
            final hw = provisioningData['hardware_settings'];
            if (hw['receipt_printer_ip'] != null) {
              final val = hw['receipt_printer_ip'].toString();
              await storage.write(key: 'PrinterIP', value: val);
              _syncedSettings['プリンターIP'] = val;
            }
            if (hw['drawer_kick_command'] != null) {
              final val = hw['drawer_kick_command'].toString();
              await storage.write(key: 'DrawerKickCommand', value: val);
              _syncedSettings['ドロワーキック'] = val;
            }
            if (hw['pos_role'] != null) {
              final val = hw['pos_role'].toString();
              await storage.write(key: 'PosRole', value: val);
              final roleLabel = val == 'host'
                  ? 'ホスト機'
                  : val == 'client'
                      ? 'クライアント機'
                      : '標準';
              _syncedSettings['POSロール'] = roleLabel;
            }
          }
          if (provisioningData['store_context'] != null) {
            final storeCtx = provisioningData['store_context'];
            if (storeCtx['store_name'] != null) {
              final val = storeCtx['store_name'].toString();
              await storage.write(key: 'StoreName', value: val);
              _syncedSettings['店舗名'] = val;
            }
            if (storeCtx['tax_rate_standard'] != null) {
              await storage.write(key: 'TaxRateStandard', value: storeCtx['tax_rate_standard'].toString());
            }
            if (storeCtx['tax_rate_reduced'] != null) {
              await storage.write(key: 'TaxRateReduced', value: storeCtx['tax_rate_reduced'].toString());
            }
            if (storeCtx['store_mode'] != null) {
              final val = storeCtx['store_mode'].toString();
              await storage.write(key: 'StoreMode', value: val);
              final modeLabel = val == 'restaurant' ? '飲食店' : val == 'retail' ? '小売店' : '標準';
              _syncedSettings['店舗モード'] = modeLabel;
            }
          }
        } catch (e) {
          debugPrint('Provisioning fetch failed: $e');
          // 設定取得に失敗してもマスタ同期は続行する
        }

        setState(() => _statusMessage = '商品マスタを確認中...');

        final syncService = ProductSyncService(
          baseUrl: baseUrl,
          authToken: authToken,
        );
        
        await syncService.syncProducts(onProgress: (count) {
          if (!mounted) return;
          setState(() {
            _processedCount = count;
            _statusMessage = '商品マスタ同期中...';
          });
        });

        // オフライン会計キューの送信を試みる
        setState(() => _statusMessage = 'オフライン会計を送信中...');
        try {
          final drained = await SentToApi().drainOfflineQueue();
          if (drained > 0) {
            _syncedSettings['オフライン送信'] = '$drained 件';
          }
        } catch (_) {
          // オフライン送信に失敗しても続行（次回の同期時に再試行）
        }

        setState(() => _statusMessage = '同期完了');
        setState(() => _isFinished = true);
      }
    } catch (e) {
      debugPrint('Provisioning Error: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _statusMessage = 'エラーが発生しました';
      });
      await Future.delayed(const Duration(seconds: 2));
      
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginTopView()),
        (route) => false,
      );
    }
  }

  void _onOkPressed() {
    if (widget.onFinished != null) {
      widget.onFinished!();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginTopView()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFinished) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(32),
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text('セットアップ完了', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                if (_syncedSettings.isNotEmpty) ...[
                  const Text('取得した設定', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const Divider(),
                  ..._syncedSettings.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key),
                        Text(e.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],
                const Text('マスタ同期', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('処理件数'),
                    Text('$_processedCount 件', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _onOkPressed,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_hasError)
              const Icon(Icons.error_outline, color: Colors.red, size: 48)
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_processedCount > 0 && !_hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '$_processedCount 件処理済み',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
