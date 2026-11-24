import 'package:flutter/material.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/operations/failed_sales_view.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../login/login_top_view.dart';
import '../provisioning/provisioning_view.dart';
import '../sale/offline_sale_repository.dart';

/// 業務中に安全に実行できる範囲の設定画面。
///
/// - サーバーURLや端末IDなど、端末のひも付け自体を変更する操作はここからは行わず、
///   ログイン前画面の「サーバー設定」に限定することで、担当者レベルの誤操作を防ぎます。
/// - ここではマスタ再同期やログアウトなど、比較的リスクの低い操作のみ提供します。
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _storage = FlutterSecureStorage();

  String? _storeName;
  String? _printerIp;
  int _offlinePendingCount = 0;
  int _offlineFailedCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 端末情報(店舗名・プリンターIP)と未送信オフライン会計件数を読み込む
  Future<void> _loadSettings() async {
    final storeName = await _storage.read(key: 'StoreName');
    final printerIp = await _storage.read(key: 'PrinterIP');
    final offlineCount = await OfflineSaleRepository().getPendingCount();
    final failedCount = await OfflineSaleRepository().getFailedCount();
    if (!mounted) return;
    setState(() {
      _storeName = storeName;
      _printerIp = printerIp;
      _offlinePendingCount = offlineCount;
      _offlineFailedCount = failedCount;
      _loading = false;
    });
  }

  // 確認したうえで業務を終え、ログイン画面へ戻る
  Future<void> _logout() async {
    final ok = await confirm(
      context,
      title: '業務を終わりますか？',
      message: 'ログイン画面に戻ります。レジを締めるときは、先に「レジ精算」を行ってください。',
      okLabel: '業務を終わる',
    );
    if (!ok || !mounted) return;

    // 端末認証情報（LoginToken, AccessUrl）は残し、従業員セッションのみ終了する。
    // これにより、一般担当者が誤って端末ひも付けを解除してしまうリスクを避けます。
    AppSession.instance.endBusiness();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginTopView()),
      (route) => false,
    );
  }

  // プロビジョニング画面を開き、マスタ再同期を行う
  void _openProvisioning() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ProvisioningPage(
          onFinished: () {
            // 設定画面からマスタ同期した場合は、スタックをメインメニューまで戻す。
            Navigator.of(ctx).popUntil((route) => route.isFirst);
          },
        ),
      ),
    );
  }

  // 端末の情報と、商品データの更新・業務終了のボタンを表示する
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader('設定'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionCard(
                  title: 'この端末',
                  child: Column(
                    children: [
                      LabelValue('店舗', _storeName ?? '未取得'),
                      LabelValue('レシートプリンター', _printerIp ?? '未設定'),
                      LabelValue('アプリのバージョン', PosApiClient.appVersion),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '会計データの送信',
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _offlinePendingCount > 0
                              ? Icons.cloud_upload
                              : Icons.cloud_done,
                          color: _offlinePendingCount > 0
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        title: Text(
                          _offlinePendingCount > 0
                              ? '未送信の会計が$_offlinePendingCount件あります'
                              : 'すべて送信済みです',
                        ),
                        subtitle: _offlinePendingCount > 0
                            ? const Text('通信できるようになると自動で送信します')
                            : null,
                      ),
                      // サーバーに拒否されたオフライン会計（自動再送しない。端末内に保持）
                      if (_offlineFailedCount > 0)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.error,
                            color: AppColors.danger,
                          ),
                          title: Text('送信できなかった会計が$_offlineFailedCount件あります'),
                          subtitle: const Text('タップして内容を確認してください'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FailedSalesView(),
                              ),
                            );
                            _loadSettings();
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '操作',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _openProvisioning,
                        icon: const Icon(Icons.sync),
                        label: const Text('商品データを更新'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('業務を終わる'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
