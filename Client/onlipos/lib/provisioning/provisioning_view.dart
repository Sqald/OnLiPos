/// 端末プロビジョニング画面。ログイン済みトークンを使って端末設定(プリンタIP・
/// POSロール・店舗情報など)を取得し、商品マスタ同期とオフライン会計送信を行う。
/// 「マスタ同期」メニューやログイン後の初回同期から呼ばれる。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../product/master_sync_api.dart';
import '../login/login_top_view.dart';
import '../sale/offline_sale_repository.dart';
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

  // 端末設定の取得、商品マスタ同期、オフライン会計送信を順に実行する
  Future<void> _exec() async {
    if (_hasError) {
      setState(() {
        _hasError = false;
        _processedCount = 0;
      });
    }
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
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SetupPage(title: '初期設定')),
          (route) => false,
        );
      } else {
        // プロビジョニング（端末設定）の取得
        setState(() => _statusMessage = '端末の設定を読み込んでいます…');
        try {
          final provisioningData = await ProvisioningApi.getProvisioning();
          if (provisioningData['hardware_settings'] != null) {
            final hw = provisioningData['hardware_settings'];
            if (hw['receipt_printer_ip'] != null) {
              final val = hw['receipt_printer_ip'].toString();
              await storage.write(key: 'PrinterIP', value: val);
              _syncedSettings['プリンター'] = val;
            }
            if (hw['drawer_kick_command'] != null) {
              final val = hw['drawer_kick_command'].toString();
              await storage.write(key: 'DrawerKickCommand', value: val);
            }
            if (hw['pos_role'] != null) {
              final val = hw['pos_role'].toString();
              await storage.write(key: 'PosRole', value: val);
              final roleLabel = val == 'host'
                  ? 'ホスト機'
                  : val == 'client'
                  ? 'クライアント機'
                  : '標準';
              _syncedSettings['端末の役割'] = roleLabel;
            }
          }
          if (provisioningData['store_context'] != null) {
            final storeCtx = provisioningData['store_context'];
            if (storeCtx['store_name'] != null) {
              final val = storeCtx['store_name'].toString();
              await storage.write(key: 'StoreName', value: val);
              _syncedSettings['店舗'] = val;
            }
            if (storeCtx['tax_rate_standard'] != null) {
              await storage.write(
                key: 'TaxRateStandard',
                value: storeCtx['tax_rate_standard'].toString(),
              );
            }
            if (storeCtx['tax_rate_reduced'] != null) {
              await storage.write(
                key: 'TaxRateReduced',
                value: storeCtx['tax_rate_reduced'].toString(),
              );
            }
            if (storeCtx['store_mode'] != null) {
              final val = storeCtx['store_mode'].toString();
              await storage.write(key: 'StoreMode', value: val);
              final modeLabel = val == 'restaurant'
                  ? '飲食店'
                  : val == 'retail'
                  ? '小売店'
                  : '標準';
              _syncedSettings['お店の種類'] = modeLabel;
            }
          }
        } catch (e) {
          debugPrint('Provisioning fetch failed: $e');
          // 設定取得に失敗してもマスタ同期は続行する
        }

        setState(() => _statusMessage = '商品データを確認しています…');

        final syncService = ProductSyncService(
          baseUrl: baseUrl,
          authToken: authToken,
        );

        await syncService.syncProducts(
          onProgress: (count) {
            if (!mounted) return;
            setState(() {
              _processedCount = count;
              _statusMessage = '商品データを読み込んでいます…';
            });
          },
        );

        // オフライン会計キューの送信を試みる
        setState(() => _statusMessage = '未送信の会計を送っています…');
        try {
          final drained = await SentToApi().drainOfflineQueue();
          if (drained > 0) {
            _syncedSettings['送信した会計'] = '$drained 件';
          }
          final failed = await OfflineSaleRepository().getFailedCount();
          if (failed > 0) {
            _syncedSettings['送信できなかった会計'] = '$failed 件（要確認）';
          }
        } catch (_) {
          // オフライン送信に失敗しても続行（次回の同期時に再試行）
        }

        setState(() => _statusMessage = '完了しました');
        AppSession.instance
          ..loadStore()
          ..refreshCounts();
        setState(() => _isFinished = true);
      }
    } catch (e) {
      debugPrint('Provisioning Error: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _statusMessage = '通信できる状態か確認して、もう一度お試しください';
      });
    }
  }

  // 完了画面のOKボタン押下時、呼び出し元のコールバックまたはログイン画面へ遷移する
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

  // 同期完了後は結果を、進行中は進捗を、失敗したらやり直しのボタンを表示する
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _isFinished
                      ? _finished()
                      : _hasError
                      ? _failed()
                      : _progress(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headline(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  );

  List<Widget> _finished() => [
    const Icon(Icons.check_circle, color: AppColors.success, size: 64),
    const SizedBox(height: 12),
    _headline('準備ができました'),
    const SizedBox(height: 16),
    for (final e in _syncedSettings.entries) LabelValue(e.key, e.value),
    LabelValue('読み込んだ商品データ', '$_processedCount 件'),
    const SizedBox(height: 24),
    ElevatedButton(onPressed: _onOkPressed, child: const Text('次へ')),
  ];

  List<Widget> _failed() => [
    const Icon(Icons.cloud_off, color: AppColors.danger, size: 64),
    const SizedBox(height: 12),
    _headline('更新できませんでした'),
    const SizedBox(height: 8),
    Text(_statusMessage, textAlign: TextAlign.center),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _exec,
      icon: const Icon(Icons.refresh),
      label: const Text('もう一度'),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: () {
        // 業務中や設定から開いた場合は、元の画面に戻る
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          _onOkPressed();
        }
      },
      child: const Text('あとで行う'),
    ),
  ];

  List<Widget> _progress() => [
    const Center(
      child: SizedBox.square(
        dimension: 56,
        child: CircularProgressIndicator(strokeWidth: 5),
      ),
    ),
    const SizedBox(height: 20),
    Text(
      _statusMessage,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
    if (_processedCount > 0)
      Text(
        '$_processedCount 件',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.secondary),
      ),
  ];
}
