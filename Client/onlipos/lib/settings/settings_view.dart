import 'package:flutter/material.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storeName = await _storage.read(key: 'StoreName');
    final printerIp = await _storage.read(key: 'PrinterIP');
    final offlineCount = await OfflineSaleRepository().getPendingCount();
    if (!mounted) return;
    setState(() {
      _storeName = storeName;
      _printerIp = printerIp;
      _offlinePendingCount = offlineCount;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('業務を終了し、ログイン画面に戻ります。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 端末認証情報（LoginToken, AccessUrl）は残し、従業員セッションのみ終了する。
    // これにより、一般担当者が誤って端末ひも付けを解除してしまうリスクを避けます。
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginTopView()),
      (route) => false,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '端末情報',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      title: const Text('店舗名'),
                      subtitle: Text(_storeName ?? '未取得'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('レシートプリンターIP'),
                      subtitle: Text(_printerIp ?? '未設定'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('未送信オフライン会計'),
                      subtitle: Text(_offlinePendingCount > 0
                          ? '$_offlinePendingCount 件（マスタ同期時に自動送信）'
                          : 'なし'),
                      trailing: _offlinePendingCount > 0
                          ? const Icon(Icons.warning_amber, color: Colors.orange)
                          : const Icon(Icons.check_circle, color: Colors.green),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '操作',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openProvisioning,
                      icon: const Icon(Icons.sync),
                      label: const Text('マスタ再同期'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('ログアウト'),
                    ),
                  ),
                  const Spacer(),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      'OnLiPos Client',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

