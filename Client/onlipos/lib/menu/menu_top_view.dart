/// ログイン後のトップメニュー画面。売上登録・レジ関連・在庫・返品・設定など
/// 各業務画面への入口をタイル状に並べる。POSの役割(ホスト/クライアント)や
/// 担当者の権限に応じて表示するタイルを出し分ける。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/login/login_top_view.dart';
import 'package:onlipos/operations/failed_sales_view.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/cash/cash_check_view.dart';
import 'package:onlipos/cash/cash_close_view.dart';
import 'package:onlipos/cash/cash_movement_view.dart';
import 'package:onlipos/cash/cash_pickup_view.dart';
import 'package:onlipos/login/employee_auth_dialog.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/inventory/inventory_inout_view.dart';
import 'package:onlipos/inventory/stock_check_view.dart';
import 'package:onlipos/operations/attendance_view.dart';
import 'package:onlipos/operations/kitchen_view.dart';
import 'package:onlipos/operations/receiving_view.dart';
import 'package:onlipos/operations/reservation_view.dart';
import 'package:onlipos/operations/stocktake_view.dart';
import 'package:onlipos/operations/void_sale_view.dart';
import 'package:onlipos/pop/pop_view.dart';
import 'package:onlipos/price/price_edit_view.dart';
import 'package:onlipos/refund/return_refund_view.dart';
import 'package:onlipos/journal/journal_list_view.dart';
import 'package:onlipos/sale/host_waiting_view.dart';
import 'package:onlipos/sale/receipt_issue_view.dart';
import 'package:onlipos/sale/store_sales_view.dart';
import 'package:onlipos/settings/settings_view.dart';

class MenuTopView extends StatefulWidget {
  final int employeeId;
  final String employeeName;
  final List<String> permissions;

  const MenuTopView({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.permissions = const [],
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
    AppSession.instance.refreshCounts();
  }

  // この端末のPOS役割(ホスト/クライアント/standard)をSecureStorageから読み込む
  Future<void> _loadPosRole() async {
    const storage = FlutterSecureStorage();
    final role = await storage.read(key: 'PosRole') ?? 'standard';
    if (mounted) setState(() => _posRole = role);
  }

  bool get _isHost => _posRole == 'host';
  // レジ金チェック: 操作する担当者を認証（cash_check 権限をサーバーで確認）してから画面を開く
  Future<void> _openCashCheck() async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: 'レジ金の点検をする人の確認',
      permission: 'cash_check',
    );
    if (operator == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            CashCheckView(employeeId: operator.id, employeeName: operator.name),
      ),
    );
  }

  // レジ精算: 操作する担当者を認証（close_register 権限をサーバーで確認）してから画面を開く
  Future<void> _openCashClose() async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: 'レジ精算をする人の確認',
      permission: 'close_register',
    );
    if (operator == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            CashCloseView(employeeId: operator.id, employeeName: operator.name),
      ),
    );
  }

  // 途中回収: 操作する担当者を認証（cash_pickup 権限をサーバーで確認）してから画面を開く
  Future<void> _openCashPickup() async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: '途中回収をする人の確認',
      permission: 'cash_pickup',
    );
    if (operator == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CashPickupView(
          employeeId: operator.id,
          employeeName: operator.name,
        ),
      ),
    );
  }

  // レジ入出金: 操作する担当者を認証（cash_pickup 権限をサーバーで確認）してから画面を開く
  Future<void> _openCashMovement() async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: '入出金をする人の確認',
      permission: 'cash_pickup',
    );
    if (operator == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CashMovementView(
          employeeId: operator.id,
          employeeName: operator.name,
        ),
      ),
    );
  }

  void _open(Widget view) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => view));

  // 担当者を認証（権限をサーバーで確認）してから画面を開く
  Future<void> _openWithAuth(
    String title,
    String permission,
    Widget Function(int employeeId) builder,
  ) async {
    final operator = await showEmployeeAuthDialog(
      context,
      title: title,
      permission: permission,
    );
    if (operator == null || !mounted) return;
    _open(builder(operator.id));
  }

  bool get _canEditPrices => widget.permissions.contains('edit_prices');
  bool get _canViewSales => widget.permissions.contains('view_sales');
  bool get _canViewJournal => widget.permissions.contains('view_journal');

  // 業務を終えてログイン画面に戻る
  Future<void> _logout() async {
    final ok = await confirm(
      context,
      title: '業務を終わりますか？',
      message: 'ログイン画面に戻ります。レジを締めるときは、先に「レジ精算」を行ってください。',
      okLabel: '業務を終わる',
    );
    if (!ok || !mounted) return;
    AppSession.instance.endBusiness();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginTopView()),
      (route) => false,
    );
  }

  // よく使う会計を大きく、そのほかは目的ごとにまとめて並べる
  List<_MenuSection> get _sections => [
    _MenuSection('お客様への対応', AppColors.primary, [
      _MenuItem(
        '返品・返金',
        Icons.replay,
        () => _open(
          ReturnRefundView(
            operatorName: widget.employeeName,
            operatorId: widget.employeeId,
          ),
        ),
      ),
      _MenuItem(
        '会計の取消',
        Icons.cancel_outlined,
        () => _openWithAuth(
          '会計の取消をする人の確認',
          'view_sales',
          (id) => VoidSaleView(employeeId: id),
        ),
      ),
      _MenuItem(
        '領収書',
        Icons.receipt_outlined,
        () => _open(
          ReceiptIssueView(
            operatorName: widget.employeeName,
            operatorId: widget.employeeId,
          ),
        ),
      ),
      _MenuItem(
        '予約',
        Icons.event_outlined,
        () => _open(const ReservationView()),
      ),
      _MenuItem(
        '厨房',
        Icons.soup_kitchen_outlined,
        () => _open(const KitchenView()),
      ),
    ]),
    _MenuSection('レジのお金', AppColors.success, [
      _MenuItem('レジ精算', Icons.lock_clock, _openCashClose, note: '閉店時'),
      _MenuItem('レジ金の点検', Icons.fact_check_outlined, _openCashCheck),
      _MenuItem('途中回収', Icons.move_to_inbox, _openCashPickup),
      _MenuItem('入出金', Icons.swap_vert, _openCashMovement),
    ]),
    _MenuSection('商品・在庫', AppColors.warning, [
      _MenuItem(
        '在庫を見る',
        Icons.warehouse_outlined,
        () => _open(const StockCheckView()),
      ),
      _MenuItem(
        '入出庫',
        Icons.inventory_2_outlined,
        () => _open(const InventoryInOutView()),
      ),
      _MenuItem(
        '入荷',
        Icons.local_shipping_outlined,
        () => _openWithAuth(
          '入荷をする人の確認',
          'inventory',
          (id) => ReceivingView(employeeId: id),
        ),
      ),
      _MenuItem(
        '棚卸',
        Icons.checklist,
        () => _openWithAuth(
          '棚卸をする人の確認',
          'inventory',
          (id) => StocktakeView(employeeId: id),
        ),
      ),
      _MenuItem(
        'POP印刷',
        Icons.local_offer_outlined,
        () => _open(const PopView()),
      ),
      if (_canEditPrices)
        _MenuItem(
          '店舗の価格',
          Icons.price_change_outlined,
          () => _open(const PriceEditView()),
        ),
    ]),
    _MenuSection('お店の管理', AppColors.secondary, [
      _MenuItem(
        '勤怠',
        Icons.badge_outlined,
        () => _open(const AttendanceView()),
      ),
      if (_canViewSales)
        _MenuItem(
          '店舗の売上',
          Icons.bar_chart,
          () => _open(const StoreSalesView()),
        ),
      if (_canViewJournal)
        _MenuItem(
          'ジャーナル',
          Icons.menu_book_outlined,
          () => _open(const JournalListView()),
        ),
      _MenuItem(
        '設定',
        Icons.settings_outlined,
        () => _open(const SettingsView()),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        'メニュー',
        subtitle: '業務開始: ${widget.employeeName} さん',
        showBack: false,
        actions: [
          if (_isHost)
            const StatusBadge('ホスト機', type: MessageType.success)
          else if (_posRole == 'client')
            const StatusBadge('クライアント機'),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('業務を終わる'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final sale = _SaleButtons(
            vertical: box.maxWidth >= 840,
            buttons: [
              (
                'お会計',
                'バーコードを読み取る',
                Icons.qr_code_scanner,
                AppColors.primary,
                () => _open(const OperatorInputView(isListView: false)),
              ),
              (
                '一覧からお会計',
                '商品を選んで登録する',
                Icons.grid_view,
                const Color(0xFF2E4A7D),
                () => _open(const OperatorInputView(isListView: true)),
              ),
              if (_isHost)
                (
                  '待ち受け',
                  'ほかの端末の会計を受ける',
                  Icons.inbox,
                  AppColors.success,
                  () => _open(
                    HostWaitingView(
                      operatorName: widget.employeeName,
                      operatorId: widget.employeeId,
                    ),
                  ),
                ),
            ],
          );
          final sections = [
            const _FailedSalesNotice(),
            for (final section in _sections) _MenuSectionView(section),
          ];
          if (box.maxWidth < 840) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [sale, const SizedBox(height: 16), ...sections],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: (box.maxWidth * 0.3).clamp(260, 380),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
                  child: sale,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 20, 20, 20),
                  children: sections,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.icon, this.onTap, {this.note});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// 「閉店時」など、使う場面の補足
  final String? note;
}

class _MenuSection {
  const _MenuSection(this.title, this.color, this.items);
  final String title;
  final Color color;
  final List<_MenuItem> items;
}

// いちばんよく使う会計のボタン（大きく表示する）
class _SaleButtons extends StatelessWidget {
  const _SaleButtons({required this.vertical, required this.buttons});

  final bool vertical;
  final List<(String, String, IconData, Color, VoidCallback)> buttons;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final (label, note, icon, color, onTap) in buttons)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: vertical ? 12 : 0,
              right: vertical ? 0 : 10,
            ),
            child: Material(
              color: color,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 52, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          note,
                          style: const TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          )
        : SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
  }
}

// 見出しと、その中の機能のボタン
class _MenuSectionView extends StatelessWidget {
  const _MenuSectionView(this.section);

  final _MenuSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 20,
                decoration: BoxDecoration(
                  color: section.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: section.items.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 78,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, i) {
              final item = section.items[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: item.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 28, color: section.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.25,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (item.note != null)
                                Text(
                                  item.note!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// サーバーに送れなかった会計があるときの案内
class _FailedSalesNotice extends StatelessWidget {
  const _FailedSalesNotice();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSession.instance,
      builder: (context, _) {
        final count = AppSession.instance.failedCount;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: AppColors.dangerSoft,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.error, color: AppColors.danger),
              title: Text('送信できなかった会計が$count件あります'),
              subtitle: const Text('内容を確認して、もう一度送信してください'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FailedSalesView()),
              ),
            ),
          ),
        );
      },
    );
  }
}
