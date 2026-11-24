/// レジ金チェック画面。
/// 営業中に金種別枚数を入力してレジ内現金の合計を算出し、
/// サーバーが計算した想定レジ金（expected_amount）と比較して差異を確認する。
/// 登録後は点検（X）レポートを印字する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/cash/denomination_form.dart';

import 'cash_log_api.dart';
import '../sale/escpos/lan_recipt_api.dart';

class CashCheckView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashCheckView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashCheckView> createState() => _CashCheckViewState();
}

class _CashCheckViewState extends State<CashCheckView> {
  final List<int> _denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1];
  final Map<int, TextEditingController> _controllers = {};

  int _totalAmount = 0;
  int? _lastAmount;
  int? _expectedAmount;
  int? _diffAmount;
  DateTime? _lastLoggedAt;
  bool _isLoading = false;
  final CashLogApi _api = CashLogApi();

  // 金種ごとの入力欄を初期化し、コンテキスト読込とドロア開放を行う
  @override
  void initState() {
    super.initState();
    for (final denomination in _denominations) {
      final controller = TextEditingController(text: '');
      controller.addListener(_calculateTotal);
      _controllers[denomination] = controller;
    }
    _loadContext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReceiptPrinter.openDrawer();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 各金種の枚数入力から合計金額を再計算する
  void _calculateTotal() {
    var total = 0;
    _controllers.forEach((denomination, controller) {
      final count = int.tryParse(controller.text) ?? 0;
      total += denomination * count;
    });

    if (!mounted) return;
    setState(() {
      _totalAmount = total;
      if (_expectedAmount != null) {
        _diffAmount = _totalAmount - (_expectedAmount ?? 0);
      }
    });
  }

  /// 前回のレジ金チェック結果と当日の想定レジ金をサーバーから取得する
  Future<void> _loadContext() async {
    final result = await _api.fetchCashCheckContext();

    if (!mounted) return;

    setState(() {
      if (result['success'] == true) {
        _lastAmount = result['last_amount'] is int
            ? result['last_amount'] as int
            : int.tryParse(result['last_amount']?.toString() ?? '');
        _expectedAmount = result['expected_amount'] is int
            ? result['expected_amount'] as int
            : int.tryParse(result['expected_amount']?.toString() ?? '');
        if (_expectedAmount != null) {
          _diffAmount = _totalAmount - _expectedAmount!;
        }
        if (result['last_logged_at'] != null) {
          _lastLoggedAt = DateTime.tryParse(
            result['last_logged_at'].toString(),
          );
        }
      }
    });
  }

  /// 入力された金種枚数からレジ金チェックを登録し、成功したら点検レポートを印字する
  Future<void> _submit() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    final cashDrawer = <int, int>{};
    _controllers.forEach((denomination, controller) {
      cashDrawer[denomination] = int.tryParse(controller.text) ?? 0;
    });

    final result = await _api.cashCheck(
      employeeId: widget.employeeId,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        // サーバー側を真実としつつ、営業日トータル差異の考え方は維持する。
        _lastAmount = result['last_amount'] is int
            ? result['last_amount'] as int
            : int.tryParse(result['last_amount']?.toString() ?? '');
        _expectedAmount = result['expected_amount'] is int
            ? result['expected_amount'] as int
            : int.tryParse(result['expected_amount']?.toString() ?? '');
        if (_expectedAmount != null) {
          _diffAmount = _totalAmount - _expectedAmount!;
        }
        if (result['last_logged_at'] != null) {
          _lastLoggedAt = DateTime.tryParse(
            result['last_logged_at'].toString(),
          );
        }
      }
    });

    if (result['success'] == true) {
      showMessage(context, 'レジ金の点検を登録しました', MessageType.success);
      // 点検（X）レポートを印字（セッションが開いている場合のみデータが返る）
      final report = await _api.fetchRegisterReport(
        employeeId: widget.employeeId,
      );
      if (report['success'] == true) {
        await ReceiptPrinter.printRegisterReport(report);
      }
    } else {
      final message = result['message']?.toString() ?? 'エラーが発生しました';
      showMessage(context, message, MessageType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diffAmount;
    final last = _lastLoggedAt?.toLocal();
    return Scaffold(
      appBar: const AppHeader('レジ金の点検', subtitle: 'レジの中の現金を数えて、枚数を入力してください'),
      body: DenominationForm(
        controllers: _controllers,
        totalLabel: 'いま数えた現金',
        total: _totalAmount,
        submitLabel: '点検の結果を登録する',
        danger: false,
        loading: _isLoading,
        onSubmit: _submit,
        details: [
          LabelValue('担当者', widget.employeeName),
          if (_expectedAmount != null) ...[
            const Divider(),
            LabelValue('あるはずの金額', yen(_expectedAmount), bold: true),
            if (diff != null)
              LabelValue(
                '過不足',
                _totalAmount == 0
                    ? '-'
                    : diff == 0
                    ? 'ぴったりです'
                    : '${diff > 0 ? '+' : ''}${yen(diff)}',
                size: 20,
                bold: true,
                color: _totalAmount == 0
                    ? null
                    : diff == 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
          ],
          if (_lastAmount != null)
            LabelValue(
              last == null
                  ? '前回数えた金額'
                  : '前回（${last.month}/${last.day} ${last.hour}:${last.minute.toString().padLeft(2, '0')}）',
              yen(_lastAmount),
            ),
        ],
      ),
    );
  }
}
