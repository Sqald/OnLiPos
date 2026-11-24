/// レジ業務中に担当者コードを入力させ、店舗モードに応じて
/// 卓番入力画面または売上（スキャン/一覧）画面へ遷移する画面。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/ui/credential_pad.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/sale/sale_scan_view.dart';
import 'package:onlipos/sale/sale_list_view.dart';
import 'package:onlipos/sale/table_number_input_view.dart';

class OperatorInputView extends StatefulWidget {
  final bool isListView;
  const OperatorInputView({super.key, this.isListView = false});

  @override
  State<OperatorInputView> createState() => _OperatorInputViewState();
}

class _OperatorInputViewState extends State<OperatorInputView> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 担当者コードを検証し、店舗モードに応じて次画面(卓番入力 or 売上画面)へ遷移する
  Future<void> _login() async {
    final operatorCode = _controller.text.trim();
    if (operatorCode.isEmpty) {
      setState(() => _error = '従業員番号を入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final operator = await LoginApi.validateOperator(operatorCode);

      if (mounted) {
        const storage = FlutterSecureStorage();
        final storeMode = await storage.read(key: 'StoreMode') ?? 'standard';

        if (!mounted) return;

        // 飲食店モード（スキャン画面のみ）：卓番入力画面を経由する
        if (!widget.isListView && storeMode == 'restaurant') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TableNumberInputView(
                operatorName: operator.name,
                operatorId: operator.id,
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => widget.isListView
                  ? SaleListView(
                      operatorName: operator.name,
                      operatorId: operator.id,
                    )
                  : SaleScanView(
                      operatorName: operator.name,
                      operatorId: operator.id,
                      storeMode: storeMode,
                    ),
            ),
          );
        }
        // operator.permissions は将来の拡張用（現在は参照しない）
      }
    } catch (e) {
      if (mounted) {
        _controller.clear();
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 従業員番号の入力欄（テンキー付き）を表示する
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        widget.isListView ? 'お会計（一覧から選ぶ）' : 'お会計',
        subtitle: '担当する人の番号を入力してください',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: SectionCard(
              title: 'だれが担当しますか？',
              child: CredentialPad(
                codeController: _controller,
                loading: _isLoading,
                error: _error,
                submitLabel: '会計を始める',
                onSubmit: _login,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
