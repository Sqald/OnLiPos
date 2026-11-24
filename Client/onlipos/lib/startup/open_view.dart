/// レジ開設画面。業務開始ログイン直後に表示され、金種別の釣銭準備金枚数を入力して
/// 開設処理を行う。開設完了後はメインメニューへ遷移する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/cash/denomination_form.dart';
import 'open_api.dart';
import '../menu/menu_top_view.dart';
import '../login/login_top_view.dart';
import '../sale/escpos/lan_recipt_api.dart';

class OpenView extends StatefulWidget {
  final int employeeId;
  final String employeeName;
  final DateTime openDate;
  final List<String> permissions;

  const OpenView({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.openDate,
    this.permissions = const [],
  });

  @override
  State<OpenView> createState() => _OpenViewState();
}

class _OpenViewState extends State<OpenView> {
  // 金種リスト
  final List<int> _denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1];

  // 各金種の枚数を管理するコントローラーのマップ
  final Map<int, TextEditingController> _controllers = {};

  int _totalAmount = 0;
  bool _isLoading = false;
  final OpenApi _openApi = OpenApi();

  @override
  void initState() {
    super.initState();
    // コントローラーの初期化とリスナー設定
    for (var denomination in _denominations) {
      var controller = TextEditingController(text: '');
      controller.addListener(_calculateTotal);
      _controllers[denomination] = controller;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReceiptPrinter.openDrawer();
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // 各金種の入力枚数から釣銭準備金の合計金額を再計算する
  void _calculateTotal() {
    int total = 0;
    _controllers.forEach((denomination, controller) {
      int count = int.tryParse(controller.text) ?? 0;
      total += denomination * count;
    });

    if (mounted) {
      setState(() {
        _totalAmount = total;
      });
    }
  }

  // 入力された金種枚数でレジ開設APIを呼び出し、成功時はメインメニューへ遷移する
  Future<void> _handleOpenStore() async {
    if (_totalAmount == 0) {
      final ok = await confirm(
        context,
        title: '釣銭準備金が0円です',
        message: 'このままレジを開設しますか？',
        okLabel: '0円で開設する',
        cancelLabel: '入力に戻る',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _isLoading = true;
    });

    // 金種ごとの枚数マップを作成
    Map<int, int> cashDrawer = {};
    _controllers.forEach((denomination, controller) {
      cashDrawer[denomination] = int.tryParse(controller.text) ?? 0;
    });

    final dateStr =
        "${widget.openDate.year}-${widget.openDate.month.toString().padLeft(2, '0')}-${widget.openDate.day.toString().padLeft(2, '0')}";

    final result = await _openApi.openStore(
      employeeId: widget.employeeId,
      openDate: dateStr,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true && mounted) {
      showMessage(context, 'レジを開設しました', MessageType.success);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MenuTopView(
            employeeId: widget.employeeId,
            employeeName: widget.employeeName,
            permissions: widget.permissions,
          ),
        ),
      );
    } else if (mounted) {
      showMessage(
        context,
        result['message']?.toString() ?? 'レジを開設できませんでした',
        MessageType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.openDate;
    return PopScope(
      canPop: false,
      child: Scaffold(
        // 戻る操作はできない（担当者を変えるにはログインからやり直す）
        appBar: AppHeader(
          'レジ開設',
          subtitle: 'はじめに、レジに入れるお釣り用の現金を数えて入力してください',
          showBack: false,
          actions: [
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginTopView()),
                    ),
              child: const Text('ログインに戻る'),
            ),
          ],
        ),
        body: DenominationForm(
          controllers: _controllers,
          totalLabel: '釣銭準備金の合計',
          total: _totalAmount,
          submitLabel: 'レジを開設する',
          loading: _isLoading,
          onSubmit: _handleOpenStore,
          details: [
            LabelValue('営業日', '${d.year}/${d.month}/${d.day}'),
            LabelValue('担当者', widget.employeeName),
          ],
        ),
      ),
    );
  }
}
