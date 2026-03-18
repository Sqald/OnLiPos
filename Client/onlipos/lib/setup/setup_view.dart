import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'setup_api.dart';
import '../provisioning/provisioning_view.dart';


class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.title});
  final String title;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _accessUrlController = TextEditingController(text: kDebugMode ? 'http://localhost:3000' : 'https://onlipos.com');
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

  @override
  Widget build(BuildContext context) {
    Widget firstLogin = Scaffold(
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
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _accessUrlController,
                  decoration: const InputDecoration(
                    labelText: 'ログイン先URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _userLoginController,
                  decoration: const InputDecoration(
                    labelText: '企業ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _storeAsciiNameController,
                  decoration: const InputDecoration(
                    labelText: '店舗ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _posTokenAsciiNameController,
                  decoration: const InputDecoration(
                    labelText: '端末ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _posTokenPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'POSパスワード',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () async {
                      if (_accessUrlController.text.isNotEmpty &&
                          _userLoginController.text.isNotEmpty &&
                          _storeAsciiNameController.text.isNotEmpty &&
                          _posTokenAsciiNameController.text.isNotEmpty &&
                          _posTokenPasswordController.text.isNotEmpty) {
                        setState(() {
                          _isLoading = true;
                        });
                        try {
                          bool ans = await Setup_Api().posLogin(
                            url: _accessUrlController.text,
                            userLogin: _userLoginController.text,
                            storeName: _storeAsciiNameController.text,
                            posName: _posTokenAsciiNameController.text,
                            posPassword: _posTokenPasswordController.text,
                          );
                          if (ans == true) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('セットアップ成功')));
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) => const ProvisioningPage(),
                              )).then((_) {
                                if (mounted) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                }
                              });
                            }
                          } else {
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ログインに失敗しました')));
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
                          }
                        }
                      } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('入力される値が不足しています。')));
                    }},
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading ? const Text('接続中') : const Text('セットアップ'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return firstLogin;
  }
}