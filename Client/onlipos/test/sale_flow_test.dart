// 会計の操作の流れ（戻る・取り消し・担当者の変更・現金会計とお釣り）を確認する
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onlipos/login/operator_input_view.dart';
import 'package:onlipos/product/product.dart';
import 'package:onlipos/sale/cart_pricing.dart';
import 'package:onlipos/sale/payment_view.dart';
import 'package:onlipos/sale/sale_scan_view.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/num_pad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _rice = Product(id: 1, code: 'A', name: '鮭おにぎり', price: 150, taxRate: 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <Map<String, dynamic>>[];

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('onlipos_flow');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<void> run(
    WidgetTester tester,
    Future<void> Function(Future<void> Function() settle) body,
  ) => http.runWithClient(
    () async {
      sent.clear();
      FlutterSecureStorage.setMockInitialValues({
        'AccessUrl': 'https://pos.example.com',
        'LoginToken': 'token',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 150));
        }
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 7));
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/sales')) {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'success': true, 'receipt_number': 'R-1'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }),
  );

  // メニューの代わりの画面から開く
  Widget app(Widget page) => MaterialApp(
    theme: buildAppTheme(),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('メニュー'),
        ),
      ),
    ),
  );

  SaleScanView scan() => SaleScanView(
    operatorName: '山田',
    operatorId: 1,
    initialItems: [ScannedItem(product: _rice, quantity: 2)],
  );

  testWidgets('商品があるときに戻ると確認し、続ける・やめるを選べる', (tester) async {
    await run(tester, (settle) async {
      await tester.pumpWidget(app(scan()));
      await tester.tap(find.text('メニュー'));
      await settle();

      await tester.tap(find.text('戻る'));
      await settle();
      expect(find.text('会計をやめますか？'), findsOneWidget);
      await tester.tap(find.text('会計を続ける'));
      await settle();
      expect(find.text('鮭おにぎり'), findsOneWidget);

      await tester.tap(find.text('戻る'));
      await settle();
      await tester.tap(find.text('会計をやめる'));
      await settle();
      expect(find.text('メニュー'), findsOneWidget);
    });
  });

  testWidgets('すべて取り消しても会計画面に残り、メニューへ戻れる', (tester) async {
    await run(tester, (settle) async {
      await tester.pumpWidget(app(scan()));
      await tester.tap(find.text('メニュー'));
      await settle();
      await tester.tap(find.text('すべて取り消す'));
      await settle();
      await tester.tap(find.text('すべて取り消す').last);
      await settle();
      expect(find.text('鮭おにぎり'), findsNothing);
      expect(find.text('商品のバーコードを読み取ってください'), findsOneWidget);

      await tester.tap(find.text('戻る'));
      await settle();
      expect(find.text('メニュー'), findsOneWidget);
    });
  });

  testWidgets('担当者を変える画面から、メニューへ戻れる', (tester) async {
    await run(tester, (settle) async {
      await tester.pumpWidget(
        app(const SaleScanView(operatorName: '山田', operatorId: 1)),
      );
      await tester.tap(find.text('メニュー'));
      await settle();
      await tester.tap(find.byTooltip('担当者を変える'));
      await settle();
      expect(find.byType(OperatorInputView), findsOneWidget);
      await tester.tap(find.text('戻る'));
      await settle();
      expect(find.text('メニュー'), findsOneWidget);
    });
  });

  testWidgets('現金でお会計: お札の候補を選ぶとお釣りを表示し、会計を送信する', (tester) async {
    await run(tester, (settle) async {
      await tester.pumpWidget(
        app(
          PaymentView(
            operatorName: '山田',
            operatorId: 1,
            items: [ScannedItem(product: _rice, quantity: 2)],
            pricing: const CartPricing(),
          ),
        ),
      );
      await tester.tap(find.text('メニュー'));
      await settle();
      await tester.tap(find.text('現金でお会計'));
      await settle();
      expect(find.byType(CashTenderView), findsOneWidget);

      await tester.tap(find.text(yen(1000)));
      await tester.pump();
      expect(find.text(yen(700)), findsOneWidget);
      await tester.tap(find.text('会計を完了する'));
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single['sale']['total_amount'], 300);
      expect(sent.single['payments'], [
        {'method': 0, 'amount': 300},
      ]);
      expect(find.text('次のお客様へ'), findsOneWidget);
      expect(find.text(yen(700)), findsOneWidget);
      await tester.tap(find.text('次のお客様へ'));
      await settle();
      expect(find.text('メニュー'), findsOneWidget);
    });
  });

  testWidgets('テンキー: 選択中の金額は打ち始めると置き換わる', (tester) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: '4120',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumPad(
            controller: controller,
            showDoubleZero: true,
            maxLength: 5,
          ),
        ),
      ),
    );
    await tester.tap(find.text('5'));
    expect(controller.text, '5');
    await tester.tap(find.text('00'));
    expect(controller.text, '500');
    await tester.tap(find.text('00'));
    await tester.tap(find.text('1'));
    expect(controller.text, '50000', reason: '桁数の上限を超えない');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    expect(controller.text, '5000');
  });

  test('金額の表示', () {
    expect(yen(1234567), '¥1,234,567');
    expect(yen(-300), '-¥300');
    expect(yen(0), '¥0');
    expect(yen(null), '-');
  });
}
