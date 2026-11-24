// すべての画面を、レジで使う画面サイズで表示し、はみ出し・例外がないことを確認する。
// 環境変数 SCREENSHOT_DIR を指定すると、画面の画像を保存する（見た目の確認用）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onlipos/cash/cash_check_view.dart';
import 'package:onlipos/cash/cash_close_view.dart';
import 'package:onlipos/cash/cash_movement_view.dart';
import 'package:onlipos/cash/cash_pickup_view.dart';
import 'package:onlipos/inventory/inventory_inout_view.dart';
import 'package:onlipos/inventory/stock_check_view.dart';
import 'package:onlipos/journal/journal_detail_view.dart';
import 'package:onlipos/journal/journal_list_view.dart';
import 'package:onlipos/login/employee_auth_dialog.dart';
import 'package:onlipos/login/login_top_view.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/menu/menu_top_view.dart';
import 'package:onlipos/operations/attendance_view.dart';
import 'package:onlipos/operations/failed_sales_view.dart';
import 'package:onlipos/operations/kitchen_view.dart';
import 'package:onlipos/operations/receiving_view.dart';
import 'package:onlipos/operations/reservation_view.dart';
import 'package:onlipos/operations/stocktake_view.dart';
import 'package:onlipos/operations/void_sale_view.dart';
import 'package:onlipos/pop/pop_view.dart';
import 'package:onlipos/price/price_edit_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/provisioning/provisioning_view.dart';
import 'package:onlipos/refund/qr_scan_receipt_view.dart';
import 'package:onlipos/refund/return_refund_view.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/host_waiting_view.dart';
import 'package:onlipos/sale/option_select_dialog.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/price_edit_dialog.dart';
import 'package:onlipos/sale/receipt_issue_view.dart';
import 'package:onlipos/sale/sale_list_view.dart';
import 'package:onlipos/sale/sale_scan_view.dart';
import 'package:onlipos/sale/store_sales_view.dart';
import 'package:onlipos/sale/table_number_input_view.dart';
import 'package:onlipos/sale/weight_input_dialog.dart';
import 'package:onlipos/settings/settings_view.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'package:onlipos/startup/open_view.dart';
import 'package:onlipos/ui/amount_dialog.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/status_footer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _screenshotDir = Platform.environment['SCREENSHOT_DIR'];
const _sizes = {
  'fullhd': Size(1920, 1080),
  'pc': Size(1280, 720),
  'tablet': Size(1024, 600),
  'small': Size(760, 400),
};

final _rice = Product(
  id: 1,
  code: '4901234510001',
  name: '鮭おにぎり',
  price: 150,
  taxRate: 8,
);
final _bento = Product(
  id: 2,
  code: '4901234510000',
  name: '幕の内弁当 特製から揚げ入り 大盛り',
  price: 1540,
  taxRate: 8,
  optionGroups: [
    OptionGroup.fromMap({
      'id': 1,
      'name': 'トッピング',
      'min_select': 0,
      'max_select': 3,
      'items': [
        {'id': 1, 'name': 'チーズ', 'price': 50},
        {'id': 2, 'name': 'たまご', 'price': 0},
      ],
    }),
  ],
);
final _meat = Product(
  id: 3,
  code: 'W001',
  name: '牛こま切れ',
  price: 398,
  taxRate: 8,
  soldByWeight: true,
);

List<ScannedItem> _cart() => [
  ScannedItem(product: _rice, quantity: 2),
  ScannedItem(product: _bento, overridePrice: 1200, discountReason: '見切り品'),
  ScannedItem(product: _meat, weightGrams: 350),
  for (var i = 0; i < 4; i++)
    ScannedItem(
      product: Product(id: 10 + i, code: 'X$i', name: '商品 $i', price: 120000),
    ),
];

// 各APIの応答（画面に中身を表示させるため）
Map<String, dynamic> _respond(String path) => switch (path) {
  _ when path.contains('verify_employee') => {
    'success': true,
    'employee_id': 1,
    'employee_name': '山田 太郎',
    'permissions': ['refund', 'view_sales'],
    'approval_token': 'x',
    'approval_permission': 'x',
  },
  _ when path.endsWith('cash_check_context') => {
    'success': true,
    'last_amount': 27000,
    'expected_amount': 48250,
    'last_logged_at': '2026-11-24T09:00:00+09:00',
  },
  _ when path.endsWith('sales/summary') => {
    'success': true,
    'total_amount': 1234567,
    'sales_count': 321,
    'refund_count': 2,
    'refund_total': 1980,
    'payment_breakdown': {'cash': 500000, 'card': 600000, 'emoney': 134567},
    'daily': [
      for (var i = 1; i < 8; i++)
        {'date': '2026-11-0$i', 'count': 10, 'amount': 120000},
    ],
    'top_products': [
      for (var i = 0; i < 8; i++)
        {'product_name': 'とても長い名前の商品 その$i', 'quantity': 12, 'amount': 4500},
    ],
  },
  _ when path.endsWith('/sales') => {
    'success': true,
    'sales': [
      for (var i = 0; i < 6; i++)
        {
          'id': i,
          'created_at': '12:3$i',
          'total_amount': 1980,
          'receipt_number': 'mihonshop-shibuya01-1-0000000$i',
          'employee_name': '佐藤 花',
          'status': i == 1 ? 'voided' : 'completed',
          'voidable': true,
        },
    ],
  },
  _ when path.endsWith('sale_by_receipt') => {
    'success': true,
    'sale': {
      'id': 1,
      'receipt_number': 'mihonshop-shibuya01-1-00000001',
      'total_amount': 58000,
      'created_at': '2026-11-24T12:34:56+09:00',
    },
    'details': [
      {
        'id': 1,
        'product_name': '幕の内弁当',
        'quantity': 3,
        'refundable_quantity': 2,
        'unit_price': 540,
        'refund_amounts': [540, 1080],
      },
      {'id': 2, 'product_name': '緑茶', 'quantity': 1, 'unit_price': 160},
    ],
  },
  _ when path.endsWith('store_stocks') => {
    'success': true,
    'stocks': [
      for (var i = 0; i < 12; i++)
        {'product_name': '商品 $i', 'product_code': '49000$i', 'quantity': i - 1},
    ],
  },
  _ when path.endsWith('kitchen_orders') => {
    'success': true,
    'kitchen_orders': [
      for (var i = 0; i < 5; i++)
        {
          'id': i,
          'table_number': '${i + 1}',
          'source': i.isEven ? 'self_order' : 'pos',
          'status': i < 3 ? 'waiting' : 'cooking',
          'created_at': '2026-11-24T12:00:00+09:00',
          'items': [
            {
              'name': 'からあげ弁当',
              'quantity': 2,
              'options': ['大盛り', 'チーズ'],
            },
            {'name': '緑茶', 'quantity': 1, 'options': <String>[]},
          ],
        },
    ],
  },
  _ when path.endsWith('attendances') => {
    'success': true,
    'attendances': [
      {
        'employee_name': '山田 太郎',
        'clock_in_at': '2026-11-24T09:00:00+09:00',
        'on_break': true,
      },
      {
        'employee_name': '佐藤 花',
        'clock_in_at': '2026-11-24T09:30:00+09:00',
        'on_break': false,
      },
    ],
  },
  _ when path.endsWith('reservations') => {
    'success': true,
    'reservations': [
      {
        'id': 1,
        'starts_at': '2026-11-24T18:00:00+09:00',
        'name': '高橋',
        'party_size': 4,
        'table_number': '3',
        'note': '窓側の席を希望',
        'status': 'booked',
      },
    ],
  },
  _ when path.endsWith('stocktakes') => {
    'success': true,
    'stocktakes': [
      {'id': 1, 'name': '2026年11月 棚卸', 'items_count': 12},
    ],
  },
  _ when path.endsWith('purchase_orders') => {
    'success': true,
    'purchase_orders': [
      {
        'id': 1,
        'number': 'PO20261124-ABCDE',
        'supplier_name': '見本食品卸',
        'items_count': 3,
        'expected_on': '2026-11-27',
      },
    ],
  },
  _ when path.contains('purchase_orders/') => {
    'success': true,
    'purchase_order': {
      'items': [
        for (var i = 0; i < 6; i++)
          {
            'id': i,
            'product_code': '49000$i',
            'product_name': '商品 $i',
            'quantity': 20,
            'received_quantity': 5,
            'remaining': 15,
          },
      ],
    },
  },
  _ when path.endsWith('journals') => {
    'success': true,
    'entries': [
      for (final (i, t) in const [
        'register_open',
        'sale',
        'refund',
        'cash_check',
        'cash_pickup',
        'register_close',
      ].indexed)
        {
          'id': i,
          'entry_type': t,
          'printed_at': '2026-11-24T1$i:00:00+09:00',
          'employee_name': '山田 太郎',
          'receipt_number': 'mihonshop-shibuya01-1-0000000$i',
          'amount': 12340,
        },
    ],
  },
  _ when path.contains('journals/') => {
    'success': true,
    'entry': {
      'entry_type': 'sale',
      'printed_at': '2026-11-24T11:00:00+09:00',
      'pos_name': 'レジ1',
      'employee_name': '山田 太郎',
      'receipt_number': 'mihonshop-shibuya01-1-00000001',
      'payload': {
        'subtotal_ex_tax': 1000,
        'tax_amount': 80,
        'total_discount': 20,
        'total_amount': 1080,
        'details': [
          {
            'product_name': '幕の内弁当',
            'quantity': 2,
            'unit_price': 540,
            'subtotal': 1080,
            'discount_amount': 20,
            'discount_reason': '見切り品',
          },
        ],
        'payments': [
          {'method': 3, 'amount': 1080},
        ],
      },
    },
  },
  _ when path.endsWith('store_prices') => {
    'success': true,
    'has_more': true,
    'last_id': 5,
    'products': [
      for (var i = 0; i < 6; i++)
        {
          'product_id': i,
          'name': '商品 $i',
          'code': '49000$i',
          'list_price': 500,
          'store_price': i.isEven ? 450 : null,
        },
    ],
  },
  _ when path.endsWith('transfer_orders') => {
    'success': true,
    'transfer_orders': [
      {
        'id': 1,
        'operator_name': '佐藤 花',
        'operator_id': 2,
        'total_amount': 3980,
        'item_count': 4,
        'table_number': '5',
        'created_at': '2026-11-24T12:00:00+09:00',
      },
    ],
  },
  _ when path.endsWith('table_orders') => {
    'success': true,
    'tables': ['1', '3', '12'],
    'table_numbers': ['1', '3', '12'],
  },
  _ => {'success': false, 'message': '通信できませんでした'},
};

Future<void> _loadFonts() async {
  if (_screenshotDir == null) return;
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  await load(
    'MaterialIcons',
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  for (final f in const [
    'Roboto',
    'Noto Sans CJK JP',
    'Segoe UI',
    'sans-serif',
  ]) {
    await load(f, Platform.environment['SCREENSHOT_FONT'] ?? '');
  }
}

Widget _app(Widget home, {GlobalKey? key}) => RepaintBoundary(
  key: key,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: withStatusFooter,
    home: home,
  ),
);

/// ダイアログを開いた状態の画面
Widget _dialog(void Function(BuildContext context) open) => Scaffold(
  body: Builder(
    builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open(context));
      return const SizedBox.expand();
    },
  ),
);

/// 戻れる画面として開く（「戻る」ボタンの表示を含めて確認する）
class _Pushed extends StatefulWidget {
  const _Pushed(this.child);
  final Widget child;
  @override
  State<_Pushed> createState() => _PushedState();
}

class _PushedState extends State<_Pushed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => widget.child,
          transitionDuration: Duration.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    final dir = Directory.systemTemp.createTempSync('onlipos_screens');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  const permissions = ['view_sales', 'edit_prices', 'view_journal'];
  PaymentView payment() => PaymentView(
    operatorName: '山田 太郎',
    operatorId: 1,
    items: _cart(),
    pricing: const CartPricing(),
  );

  final screens = <String, Widget Function()>{
    '01_setup': () => const SetupPage(title: '初期設定'),
    '02_login': () => const LoginTopView(),
    '03_open': () => OpenView(
      employeeId: 1,
      employeeName: '山田 太郎',
      openDate: DateTime(2026, 11, 24),
    ),
    '04_menu': () => const MenuTopView(
      employeeId: 1,
      employeeName: '山田 太郎',
      permissions: permissions,
    ),
    '05_operator': () => const _Pushed(OperatorInputView()),
    '06_scan_empty': () =>
        const _Pushed(SaleScanView(operatorName: '山田 太郎', operatorId: 1)),
    '07_scan': () => _Pushed(
      SaleScanView(
        operatorName: '山田 太郎',
        operatorId: 1,
        storeMode: 'retail',
        initialItems: _cart(),
      ),
    ),
    '08_scan_restaurant': () => const _Pushed(
      SaleScanView(
        operatorName: '山田 太郎',
        operatorId: 1,
        storeMode: 'restaurant',
        tableNumber: '3',
      ),
    ),
    '09_list': () =>
        const _Pushed(SaleListView(operatorName: '山田 太郎', operatorId: 1)),
    '10_payment': () => _Pushed(payment()),
    '11_tender': () => const _Pushed(
      CashTenderView(totalCashAmount: 4120, operatorName: '山田 太郎'),
    ),
    '12_table': () => const _Pushed(
      TableNumberInputView(operatorName: '山田 太郎', operatorId: 1),
    ),
    '13_host': () =>
        const _Pushed(HostWaitingView(operatorName: '山田 太郎', operatorId: 1)),
    '14_cash_check': () =>
        const _Pushed(CashCheckView(employeeId: 1, employeeName: '山田 太郎')),
    '15_cash_close': () =>
        const _Pushed(CashCloseView(employeeId: 1, employeeName: '山田 太郎')),
    '16_pickup': () =>
        const _Pushed(CashPickupView(employeeId: 1, employeeName: '山田 太郎')),
    '17_movement': () =>
        const _Pushed(CashMovementView(employeeId: 1, employeeName: '山田 太郎')),
    '18_refund': () => const _Pushed(ReturnRefundView()),
    '19_qr': () => const _Pushed(QrScanReceiptView()),
    '20_void': () => const _Pushed(VoidSaleView(employeeId: 1)),
    '21_receipt': () =>
        const _Pushed(ReceiptIssueView(operatorName: '山田 太郎', operatorId: 1)),
    '22_stock': () => const _Pushed(StockCheckView()),
    '23_inout': () => const _Pushed(InventoryInOutView()),
    '24_receiving': () => const _Pushed(ReceivingView(employeeId: 1)),
    '25_stocktake': () => const _Pushed(StocktakeView(employeeId: 1)),
    '26_pop': () => const _Pushed(PopView()),
    '27_price': () => const _Pushed(PriceEditView()),
    '28_attendance': () => const _Pushed(AttendanceView()),
    '29_reservation': () => const _Pushed(ReservationView()),
    '30_kitchen': () => const _Pushed(KitchenView()),
    '31_sales': () => const _Pushed(StoreSalesView()),
    '32_journal': () => const _Pushed(JournalListView()),
    '33_journal_detail': () => const _Pushed(
      JournalDetailView(
        employeeId: 1,
        summary: {'id': 1, 'entry_type': 'sale'},
      ),
    ),
    '34_settings': () => const _Pushed(SettingsView()),
    '35_failed': () => const _Pushed(FailedSalesView()),
    '36_sync': () => const ProvisioningPage(),
    '40_auth_dialog': () => _dialog(
      (c) => showEmployeeAuthDialog(
        c,
        title: '返品の確認（1人目）',
        permission: 'refund',
        allowOffline: true,
      ),
    ),
    '41_amount_dialog': () => _dialog(
      (c) => showAmountDialog(c, title: 'カードで支払う金額', initial: 4120, max: 4120),
    ),
    '42_price_dialog': () => _dialog(
      (c) => showDialog<void>(
        context: c,
        builder: (_) => PriceEditDialog(product: _bento),
      ),
    ),
    '43_weight_dialog': () => _dialog(
      (c) => showDialog<void>(
        context: c,
        builder: (_) => WeightInputDialog(product: _meat),
      ),
    ),
    '44_option_dialog': () => _dialog((c) => showOptionSelectDialog(c, _bento)),
    '45_confirm': () => _dialog(
      (c) => confirm(
        c,
        title: '会計をやめますか？',
        message: '登録した3点は取り消されます。',
        danger: true,
      ),
    ),
  };

  /// 権限の確認が必要な画面は、確認後の中身まで表示する
  const afterAuth = {'23_inout', '27_price', '31_sales', '32_journal'};

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
      testWidgets('$name を $sizeName で表示できる', (tester) async {
        await http.runWithClient(
          () async {
            FlutterSecureStorage.setMockInitialValues({
              'AccessUrl': 'https://pos.example.com',
              'LoginToken': 'token',
              'StoreName': '渋谷本店',
              'ReceiptPosId': '1',
            });
            AppSession.instance
              ..operatorName = '山田 太郎'
              ..businessDate = DateTime(2026, 11, 24)
              ..online = true
              ..pendingCount = 2
              ..failedCount = 1;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            final key = GlobalKey();
            Future<void> settle() async {
              for (var i = 0; i < 6; i++) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 8)),
                );
                await tester.pump(const Duration(milliseconds: 120));
              }
            }

            await tester.pumpWidget(_app(build(), key: key));
            await settle();
            if (afterAuth.contains(name)) {
              final fields = find.byType(TextField);
              await tester.enterText(fields.at(0), '1001');
              await tester.enterText(fields.at(1), '1234');
              final open = find.text('開く');
              await tester.ensureVisible(open);
              await tester.tap(open);
              await settle();
            }
            expect(tester.takeException(), isNull);
            expect(find.byType(StatusFooter), findsOneWidget);

            if (_screenshotDir != null) {
              await tester.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File('$_screenshotDir/${name}_$sizeName.png')
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(png!.buffer.asUint8List());
              });
            }
            // 残っているタイマー（自動更新・時計）を止める
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
          },
          () => MockClient(
            (request) async => http.Response.bytes(
              utf8.encode(jsonEncode(_respond(request.url.path))),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
      });
    }
  }
}
