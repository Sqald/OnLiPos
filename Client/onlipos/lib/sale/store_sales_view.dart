import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/sale/store_sales_api.dart';

class StoreSalesView extends StatefulWidget {
  const StoreSalesView({super.key});

  @override
  State<StoreSalesView> createState() => _StoreSalesViewState();
}

class _StoreSalesViewState extends State<StoreSalesView> {
  // --- 認証フェーズ ---
  bool _authenticated = false;
  bool _isAuthenticating = false;
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();

  // --- 売上表示フェーズ ---
  bool _isLoading = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _data;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final code = _codeController.text.trim();
    final pin = _pinController.text.trim();

    if (code.isEmpty || pin.isEmpty) {
      _showError('担当者コードとパスワードを入力してください');
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final result = await LoginApi.verifyEmployee(code: code, pin: pin);
      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _authenticated = true;
          _isAuthenticating = false;
        });
        _loadSales();
      } else {
        setState(() => _isAuthenticating = false);
        _showError(result['message']?.toString() ?? '認証に失敗しました');
      }
    } catch (e) {
      if (mounted) setState(() => _isAuthenticating = false);
      _showError('認証中にエラーが発生しました');
    }
  }

  Future<void> _loadSales() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final result = await StoreSalesApi.fetchSales(date: dateStr);

    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['message']?.toString() ?? 'エラーが発生しました';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadSales();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return '現金';
      case 'card':
        return 'カード';
      case 'barcode':
        return 'バーコード';
      default:
        return method ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('売上確認')),
      body: _authenticated ? _buildSalesBody() : _buildAuthBody(),
    );
  }

  // ---- 認証画面 ----
  Widget _buildAuthBody() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'パスワードが設定された担当者のみアクセスできます',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '担当者コード',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'パスワード',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _authenticate(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isAuthenticating ? null : _authenticate,
                  child: _isAuthenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('認証して開く'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 売上一覧画面 ----
  Widget _buildSalesBody() {
    final dateLabel =
        '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // 日付選択バー
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 18),
              const SizedBox(width: 8),
              Text(dateLabel, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _pickDate,
                child: const Text('日付変更'),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadSales,
                tooltip: '再読み込み',
              ),
            ],
          ),
        ),
        // 集計バー
        if (_data != null)
          Container(
            color: const Color(0xFF2D89EF),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(
                  '合計: ¥${_formatAmount(_data!['total_amount'])}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 24),
                Text(
                  '件数: ${_data!['count']}件',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        // 明細リスト
        Expanded(
          child: _buildList(),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSales, child: const Text('再試行')),
          ],
        ),
      );
    }
    final sales = (_data?['sales'] as List?) ?? [];
    if (sales.isEmpty) {
      return const Center(child: Text('この日の売上はありません'));
    }
    return ListView.separated(
      itemCount: sales.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = sales[index] as Map<String, dynamic>;
        return ListTile(
          leading: Text(
            s['created_at']?.toString() ?? '',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          title: Text(
            '¥${_formatAmount(s['total_amount'])}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${_paymentMethodLabel(s['payment_method']?.toString())}  /${s['employee_name'] ?? '-'}',
          ),
          trailing: Text(
            s['receipt_number']?.toString() ?? '',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        );
      },
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final n = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}
