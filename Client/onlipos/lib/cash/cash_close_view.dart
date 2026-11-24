/// レジ精算（締め）画面。
/// 営業終了時に金種別枚数を入力してレジ内現金の合計を算出し、
/// サーバーへ精算を登録して精算（Z）レポートを印字する。
/// 精算完了後はログアウトまたはアプリ終了を選択させる。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/cash/denomination_form.dart';
import 'package:flutter/services.dart';

import '../login/login_top_view.dart';
import '../sale/escpos/lan_recipt_api.dart';
import 'cash_log_api.dart';

class CashCloseView extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  const CashCloseView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<CashCloseView> createState() => _CashCloseViewState();
}

class _CashCloseViewState extends State<CashCloseView> {
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

  /// 入力された金種枚数でレジを精算し、成功したら精算（Z）レポートを印字して完了ダイアログを表示する
  Future<void> _submit() async {
    if (_isLoading) return;

    final diff = _diffAmount ?? 0;
    final ok = await confirm(
      context,
      title: 'レジを精算しますか？',
      message:
          '数えた現金: ${yen(_totalAmount)}\n'
          '${_diffAmount == null ? '' : '過不足: ${diff == 0 ? 'なし' : yen(diff)}\n'}'
          '精算すると、今日の会計はこれ以上入力できません。',
      okLabel: '精算する',
      cancelLabel: 'もう一度数える',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    final cashDrawer = <int, int>{};
    _controllers.forEach((denomination, controller) {
      cashDrawer[denomination] = int.tryParse(controller.text) ?? 0;
    });

    final result = await _api.closeRegister(
      employeeId: widget.employeeId,
      cashDrawer: cashDrawer,
      totalAmount: _totalAmount,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
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

    if (result['success'] == true) {
      // 精算（Z）レポートを印字（サーバーで確定保存されたスナップショットを取得）
      final session = result['register_session'];
      if (session is Map && session['z_number'] != null) {
        final zNumber = (session['z_number'] as num).toInt();
        final report = await _api.fetchRegisterReport(
          employeeId: widget.employeeId,
          zNumber: zNumber,
        );
        if (report['success'] == true) {
          await ReceiptPrinter.printRegisterReport(report);
        }
      }
      if (!mounted) return;
      _showClosingDialog();
    } else {
      final message = result['message']?.toString() ?? 'エラーが発生しました';
      showMessage(context, message, MessageType.error);
    }
  }

  // 精算完了後にログアウトまたはアプリ終了を選ばせるダイアログを表示する
  void _showClosingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('レジ精算が完了しました'),
        content: const Text('お疲れさまでした。このあとどうしますか？'),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('ログイン画面に戻る'),
            onPressed: () {
              Navigator.of(ctx).pop();
              AppSession.instance.endBusiness();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginTopView()),
                (route) => false,
              );
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.power_settings_new),
            label: const Text('アプリを終了する'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (kIsWeb) {
                SystemNavigator.pop();
              } else if (Platform.isAndroid || Platform.isIOS) {
                SystemNavigator.pop();
              } else {
                exit(0);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diffAmount;
    final last = _lastLoggedAt?.toLocal();
    return Scaffold(
      appBar: const AppHeader('レジ精算', subtitle: '閉店時に、レジの中の現金をすべて数えて入力してください'),
      body: DenominationForm(
        controllers: _controllers,
        totalLabel: 'いま数えた現金',
        total: _totalAmount,
        submitLabel: '精算を確定する',
        danger: true,
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
