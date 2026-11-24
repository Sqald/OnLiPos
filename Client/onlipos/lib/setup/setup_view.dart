/// 初回セットアップ画面。ログイントークンが存在しない状態で起動され、
/// 接続先URL・企業ID・店舗ID・端末ID・POSパスワードを入力してPOS端末認証を行う。
/// 成功したらプロビジョニング画面へ遷移し、端末設定・商品マスタを取得する。
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';

import 'setup_api.dart';
import '../provisioning/provisioning_view.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.title});
  final String title;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _accessUrlController = TextEditingController(
    text: kDebugMode ? 'http://localhost:3000' : 'https://onlipos.com',
  );
  final _userLoginController = TextEditingController();
  final _storeAsciiNameController = TextEditingController();
  final _posTokenAsciiNameController = TextEditingController();
  final _posTokenPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _accessUrlController.dispose();
    _userLoginController.dispose();
    _storeAsciiNameController.dispose();
    _posTokenAsciiNameController.dispose();
    _posTokenPasswordController.dispose();
    super.dispose();
  }

  // 接続先URLを検証する。http/https 以外は拒否し、暗号化されない http の場合は
  // POSパスワードと端末認証トークンが平文で送信される旨を確認してから続行する
  Future<bool> _confirmAccessUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      showMessage(context, '接続先は https:// で始まる形式で入力してください', MessageType.error);
      return false;
    }
    if (uri.scheme == 'https' ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1') {
      return true;
    }

    return confirm(
      context,
      title: '暗号化されていない接続です',
      message:
          'http:// の接続先では、パスワードなどが暗号化されずに送られます。\n'
          '社内LANなど信頼できるネットワークでだけ使ってください。続けますか？',
      okLabel: '続ける',
      danger: true,
    );
  }

  // 入力内容で端末の認証を行い、成功したら設定・商品データの取得へ進む
  Future<void> _submit() async {
    final fields = [
      _accessUrlController,
      _userLoginController,
      _storeAsciiNameController,
      _posTokenAsciiNameController,
      _posTokenPasswordController,
    ];
    if (fields.any((c) => c.text.trim().isEmpty)) {
      showMessage(context, 'すべての項目を入力してください', MessageType.error);
      return;
    }
    if (!await _confirmAccessUrl(_accessUrlController.text.trim())) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final ok = await SetupApi().posLogin(
        url: _accessUrlController.text.trim(),
        userLogin: _userLoginController.text.trim(),
        storeName: _storeAsciiNameController.text.trim(),
        posName: _posTokenAsciiNameController.text.trim(),
        posPassword: _posTokenPasswordController.text,
      );
      if (!mounted) return;
      if (ok != true) {
        showMessage(
          context,
          'ログインできませんでした。IDとパスワード、パスワードの期限を確認してください',
          MessageType.error,
        );
        return;
      }
      showMessage(context, '端末を登録しました', MessageType.success);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProvisioningPage()));
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().replaceFirst('Exception: ', '');
      showMessage(context, '接続できませんでした（$text）', MessageType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    bool obscure = false,
    IconData? icon,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _isLoading ? null : _submit() : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        widget.title,
        subtitle: '管理画面の「POS端末」に表示されている内容を入力してください',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, box) {
                final ids = [
                  _field(
                    _userLoginController,
                    '企業ID',
                    icon: Icons.business,
                    helper: '管理画面のホームに表示されています',
                  ),
                  _field(
                    _storeAsciiNameController,
                    '店舗ID',
                    icon: Icons.storefront,
                  ),
                  _field(
                    _posTokenAsciiNameController,
                    '端末ID',
                    icon: Icons.tablet_android,
                  ),
                ];
                final rest = [
                  _field(
                    _posTokenPasswordController,
                    'パスワード',
                    obscure: true,
                    icon: Icons.lock,
                    helper: '端末を登録したときに表示された6桁の数字（2週間有効）',
                    last: true,
                  ),
                  ExpansionTile(
                    shape: const Border(),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('接続先', style: TextStyle(fontSize: 16)),
                    subtitle: Text(_accessUrlController.text),
                    children: [
                      _field(
                        _accessUrlController,
                        '接続先のURL',
                        icon: Icons.link,
                        helper: '通常は変更しません',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      child: Text(
                        _isLoading ? '接続しています…' : 'この端末を登録する',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: box.maxWidth < 640
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [...ids, ...rest],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Column(children: ids)),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: rest,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
