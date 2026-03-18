import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'package:onlipos/startup/open_view.dart';
import 'package:onlipos/provisioning/provisioning_view.dart';

class LoginTopView extends StatefulWidget {
  const LoginTopView({Key? key}) : super(key: key);

  @override
  _LoginTopViewState createState() => _LoginTopViewState();
}

class _LoginTopViewState extends State<LoginTopView> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  String _errorMessage = '';

  // 取得した従業員情報を保持する変数
  int? _employeeId;
  String? _employeeName;

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // login_api.dart の関数を呼び出し
    final result = await LoginApi.userLogin(
      code: _codeController.text,
      pin: _pinController.text,
      openDate:
          "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      // 成功時：変数に保存
      _employeeId = result['employee_id'];
      _employeeName = result['employee_name'];

      // 変数を使って次の処理へ渡す
      _proceedToNextStep();
    } else {
      // 失敗時：エラーメッセージを更新
      setState(() {
        _errorMessage = result['message'] ?? '認証に失敗しました';
      });
    }
  }

  void _proceedToNextStep() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OpenView(
          employeeId: _employeeId!,
          employeeName: _employeeName!,
          openDate: _selectedDate,
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '業務開始・ログイン',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage,
                        style: const TextStyle(color: Colors.red)),
                  ),
                InkWell(
                  onTap: () => _selectDate(context),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '営業日 (開設日)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(dateStr, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: '従業員コード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: 'PINコード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('業務開始'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SetupPage(title: 'サーバー設定'),
                          ),
                        );
                      },
                      child: const Text('サーバー設定'),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ProvisioningPage(),
                          ),
                        );
                      },
                      child: const Text('マスタ同期'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}