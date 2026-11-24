/// ログイン後の最初の画面。営業日・従業員コード・PINを入力して業務開始ログインを行い、
/// 成功したらレジ開設画面(OpenView)へ遷移する。サーバー設定・マスタ同期画面への
/// 導線もここに置く。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/credential_pad.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'package:onlipos/startup/open_view.dart';
import 'package:onlipos/provisioning/provisioning_view.dart';

class LoginTopView extends StatefulWidget {
  const LoginTopView({super.key});

  @override
  State<LoginTopView> createState() => _LoginTopViewState();
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
  List<String> _permissions = [];

  // 従業員コード・PIN・営業日でログインAPIを呼び出す
  Future<void> _handleLogin() async {
    if (_codeController.text.trim().isEmpty || _pinController.text.isEmpty) {
      setState(() => _errorMessage = '従業員番号とPINを入力してください');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // login_api.dart の関数を呼び出し
    // ログイン後はそのままレジ開設を行うため、開設権限をサーバー側で確認する
    final result = await LoginApi.userLogin(
      code: _codeController.text,
      pin: _pinController.text,
      permission: 'open_register',
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
      _permissions =
          (result['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // 変数を使って次の処理へ渡す
      _proceedToNextStep();
    } else {
      // 失敗時：エラーメッセージを更新
      setState(() {
        _errorMessage = result['message'] ?? '認証に失敗しました';
        _pinController.clear();
      });
    }
  }

  // ログイン成功後、レジ開設画面(OpenView)へ遷移する
  void _proceedToNextStep() {
    if (!mounted) return;
    AppSession.instance.startBusiness(
      operatorName: _employeeName!,
      date: _selectedDate,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OpenView(
          employeeId: _employeeId!,
          employeeName: _employeeName!,
          openDate: _selectedDate,
          permissions: _permissions,
        ),
      ),
    );
  }

  // 営業日(開設日)の選択ダイアログを表示する
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

  // 営業日・従業員番号・PINの入力と、業務開始ボタンを表示する
  @override
  Widget build(BuildContext context) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final d = _selectedDate;
    final dateStr =
        '${d.year}年${d.month}月${d.day}日（${weekdays[d.weekday - 1]}）';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                const Text(
                  'OnLiPos',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const Text(
                  '業務を始めます。従業員番号とPINを入力してください。',
                  style: TextStyle(fontSize: 16, color: AppColors.secondary),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CredentialPad(
                      codeController: _codeController,
                      pinController: _pinController,
                      loading: _isLoading,
                      error: _errorMessage,
                      submitLabel: '業務を始める',
                      onSubmit: _handleLogin,
                      leading: InkWell(
                        onTap: () => _selectDate(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '営業日',
                            prefixIcon: Icon(Icons.calendar_today),
                            suffixIcon: Icon(Icons.edit),
                          ),
                          child: Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('商品データを更新'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ProvisioningPage(),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.settings_ethernet),
                      label: const Text('接続先・端末の設定'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const SetupPage(title: '接続先・端末の設定'),
                        ),
                      ),
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
