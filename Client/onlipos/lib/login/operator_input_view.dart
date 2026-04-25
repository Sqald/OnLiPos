import 'package:flutter/material.dart';
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
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final operatorCode = _controller.text;
    if (operatorCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('担当者コードを入力してください。'), backgroundColor: Colors.red),
      );
      _focusNode.requestFocus();
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('担当者コード入力'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('担当者コードを入力してください', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 20),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '担当者コード',
                  ),
                  onSubmitted: (value) => _login(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 300,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _login,
                        child: const Text('確定'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
