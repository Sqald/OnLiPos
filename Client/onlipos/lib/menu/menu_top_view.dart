import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/cash/cash_check_view.dart';
import 'package:onlipos/cash/cash_close_view.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/inventory/inventory_inout_view.dart';
import 'package:onlipos/refund/return_refund_view.dart';
import 'package:onlipos/sale/host_waiting_view.dart';
import 'package:onlipos/settings/settings_view.dart';

class MenuTopView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const MenuTopView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<MenuTopView> createState() => _MenuTopViewState();
}

class _MenuTopViewState extends State<MenuTopView> {
  String _posRole = 'standard';

  @override
  void initState() {
    super.initState();
    _loadPosRole();
  }

  Future<void> _loadPosRole() async {
    const storage = FlutterSecureStorage();
    final role = await storage.read(key: 'PosRole') ?? 'standard';
    if (mounted) setState(() => _posRole = role);
  }

  bool get _isHost => _posRole == 'host';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Windows 8 (Metro UI) 風のダーク背景
      backgroundColor: const Color(0xFF1D1D1D),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('メインメニュー'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isHost)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.computer, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('ホスト機', style: TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          if (_posRole == 'client')
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2D89EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tablet_android, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('クライアント機', style: TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                '担当: ${widget.employeeName}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '業務を選択してください',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3, // 横に並べる数（タブレット想定）
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.3, // タイルの比率（横長）
                children: [
                  // 売上登録ボタン（メイン機能）
                  _MenuTile(
                    title: '売上登録\n(スキャン)',
                    icon: Icons.point_of_sale,
                    color: const Color(0xFF2D89EF), // Metro Blue
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const OperatorInputView(isListView: false),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    title: '売上登録\n(一覧)',
                    icon: Icons.list_alt,
                    color: const Color(0xFF2B5797), // Metro Dark Blue
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const OperatorInputView(isListView: true),
                        ),
                      );
                    },
                  ),
                  // ホスト機のみ：待ち受けモード
                  if (_isHost)
                    _MenuTile(
                      title: '待ち受け\nモード',
                      icon: Icons.inbox,
                      color: const Color(0xFF107C10), // Metro Green
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => HostWaitingView(
                              operatorName: widget.employeeName,
                              operatorId: widget.employeeId,
                            ),
                          ),
                        );
                      },
                    )
                  else
                    _MenuTile(
                      title: 'レジ金チェック',
                      icon: Icons.account_balance_wallet,
                      color: const Color(0xFFE3A21A), // Metro Orange
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CashCheckView(
                              employeeId: widget.employeeId,
                              employeeName: widget.employeeName,
                            ),
                          ),
                        );
                      },
                    ),
                  // ホスト機は待ち受けタイルを追加したのでレジ金チェックを次の行に
                  if (_isHost)
                    _MenuTile(
                      title: 'レジ金チェック',
                      icon: Icons.account_balance_wallet,
                      color: const Color(0xFFE3A21A), // Metro Orange
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CashCheckView(
                              employeeId: widget.employeeId,
                              employeeName: widget.employeeName,
                            ),
                          ),
                        );
                      },
                    ),
                  _MenuTile(
                    title: 'レジ精算',
                    icon: Icons.receipt_long,
                    color: const Color(0xFF00A300), // Metro Green
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CashCloseView(
                            employeeId: widget.employeeId,
                            employeeName: widget.employeeName,
                          ),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    title: '入出荷管理',
                    icon: Icons.inventory_2,
                    color: const Color(0xFF1BA1E2), // Metro Light Blue
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const InventoryInOutView(),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    title: '返品・返金',
                    icon: Icons.replay,
                    color: const Color(0xFFE91E63), // Pink
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ReturnRefundView(
                            operatorName: widget.employeeName,
                            operatorId: widget.employeeId,
                          ),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    title: '設定',
                    icon: Icons.settings,
                    color: const Color(0xFF603CBA), // Metro Purple
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsView(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MenuTile({
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = onTap != null ? color : color.withOpacity(0.4);

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(0),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
