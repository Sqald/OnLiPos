// 店舗売上閲覧画面。「店舗売上閲覧」権限を持つ担当者コード＋パスワードで
// 認証した後、今日/今月/期間指定の売上サマリーを表示する。
import 'package:flutter/material.dart';
import 'package:onlipos/login/login_api.dart';
import 'package:onlipos/sale/store_sales_api.dart';

enum _PeriodMode { today, thisMonth, custom }

class StoreSalesView extends StatefulWidget {
  const StoreSalesView({super.key});

  @override
  State<StoreSalesView> createState() => _StoreSalesViewState();
}

class _StoreSalesViewState extends State<StoreSalesView> {
  // 認証フェーズ
  bool _authenticated = false;
  bool _isAuthenticating = false;
  int? _employeeId;
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();

  // 期間
  _PeriodMode _periodMode = _PeriodMode.today;
  DateTimeRange _customRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );

  // データ
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _data;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  ({String from, String to}) get _range {
    final today = DateTime.now();
    return switch (_periodMode) {
      _PeriodMode.today => (from: _dateStr(today), to: _dateStr(today)),
      _PeriodMode.thisMonth => (
        from: _dateStr(DateTime(today.year, today.month, 1)),
        to: _dateStr(today),
      ),
      _PeriodMode.custom => (
        from: _dateStr(_customRange.start),
        to: _dateStr(_customRange.end),
      ),
    };
  }

  // 担当者コード＋パスワードで認証し、成功したら売上サマリーを読み込む
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
          _employeeId = result['employee_id'] as int?;
          _isAuthenticating = false;
        });
        _loadSummary();
      } else {
        setState(() => _isAuthenticating = false);
        _showError(result['message']?.toString() ?? '認証に失敗しました');
      }
    } catch (_) {
      if (mounted) setState(() => _isAuthenticating = false);
      _showError('認証中にエラーが発生しました');
    }
  }

  // 現在選択中の期間で売上サマリーAPIを呼び出し、結果を画面に反映する
  Future<void> _loadSummary() async {
    final eid = _employeeId;
    if (eid == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final r = _range;
    final result = await StoreSalesApi.fetchSummary(
      employeeId: eid,
      from: r.from,
      to: r.to,
    );

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

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (range != null) {
      setState(() {
        _customRange = range;
        _periodMode = _PeriodMode.custom;
      });
      _loadSummary();
    }
  }

  void _setPeriod(_PeriodMode mode) {
    setState(() => _periodMode = mode);
    _loadSummary();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('店舗売上')),
      body: _authenticated ? _buildBody() : _buildAuthBody(),
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
              const Icon(Icons.bar_chart, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '「店舗売上閲覧」権限が必要です',
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

  // ---- メイン画面 ----
  Widget _buildBody() {
    return Column(
      children: [
        _buildPeriodBar(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildPeriodBar() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _PeriodBtn(
            label: '今日',
            selected: _periodMode == _PeriodMode.today,
            onTap: () => _setPeriod(_PeriodMode.today),
          ),
          const SizedBox(width: 8),
          _PeriodBtn(
            label: '今月',
            selected: _periodMode == _PeriodMode.thisMonth,
            onTap: () => _setPeriod(_PeriodMode.thisMonth),
          ),
          const SizedBox(width: 8),
          _PeriodBtn(
            label: 'カスタム',
            selected: _periodMode == _PeriodMode.custom,
            onTap: _pickCustomRange,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSummary,
            tooltip: '再読み込み',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSummary, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_data == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(),
          const SizedBox(height: 12),
          _buildPaymentCard(),
          if ((_data!['refund_count'] as int? ?? 0) > 0) ...[
            const SizedBox(height: 12),
            _buildRefundCard(),
          ],
          const SizedBox(height: 16),
          _buildDailySection(),
          const SizedBox(height: 16),
          _buildTopProductsSection(),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    final total = _data!['total_amount'] as int? ?? 0;
    final count = _data!['sales_count'] as int? ?? 0;
    final r = _range;
    final period = r.from == r.to ? r.from : '${r.from} 〜 ${r.to}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D89EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '¥${_fmt(total)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$count 件',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    final b = (_data!['payment_breakdown'] as Map<String, dynamic>?) ?? {};
    final cash = b['cash'] as int? ?? 0;
    final card = b['card'] as int? ?? 0;
    final barcode = b['barcode'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('支払方法内訳', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            _AmountRow(label: '現金', amount: cash),
            _AmountRow(label: 'カード', amount: card),
            _AmountRow(label: 'バーコード決済', amount: barcode),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundCard() {
    final count = _data!['refund_count'] as int? ?? 0;
    final total = _data!['refund_total'] as int? ?? 0;

    return Card(
      color: Colors.pink[50],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.replay, color: Colors.pink),
            const SizedBox(width: 8),
            Text('返品: $count 件', style: const TextStyle(color: Colors.pink)),
            const Spacer(),
            Text(
              '¥${_fmt(total)}',
              style: const TextStyle(
                color: Colors.pink,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailySection() {
    final daily = (_data!['daily'] as List?) ?? [];
    if (daily.length <= 1) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '日別売上',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...daily.map((d) {
          final item = d as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  item['date']?.toString() ?? '',
                  style: const TextStyle(color: Colors.grey),
                ),
                const Spacer(),
                Text('${item['count']}件'),
                const SizedBox(width: 16),
                SizedBox(
                  width: 100,
                  child: Text(
                    '¥${_fmt(item['amount'] as int? ?? 0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTopProductsSection() {
    final products = (_data!['top_products'] as List?) ?? [];
    if (products.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '売上上位商品',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...products.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final p = entry.value as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$idx.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: Text(
                    p['product_name']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${p['quantity']}個',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 90,
                  child: Text(
                    '¥${_fmt(p['amount'] as int? ?? 0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

class _PeriodBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF2D89EF) : null,
        foregroundColor: selected ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final int amount;

  const _AmountRow({required this.label, required this.amount});

  String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text(
            '¥${_fmt(amount)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
