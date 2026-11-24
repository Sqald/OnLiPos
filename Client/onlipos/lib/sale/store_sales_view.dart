// 店舗売上閲覧画面。「店舗売上閲覧」権限を持つ担当者コード＋パスワードで
// 認証した後、今日/今月/期間指定の売上サマリーを表示する。
import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/login/operator_sign_in_panel.dart';
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
  int? _employeeId;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader('店舗の売上'),
      body: _authenticated
          ? _buildBody()
          : OperatorSignInPanel(
              icon: Icons.bar_chart,
              message: '売上を見るには、「店舗売上閲覧」の権限を持つ人の確認が必要です。',
              permission: 'view_sales',
              onAuthenticated: (id, name) {
                setState(() {
                  _authenticated = true;
                  _employeeId = id;
                });
                _loadSummary();
              },
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

  static const _paymentLabels = {
    'cash': '現金',
    'card': 'カード',
    'barcode': 'バーコード決済',
    'emoney': '電子マネー',
    'points': 'ポイント',
    'voucher': '商品券',
    'house_account': '掛売',
  };

  Widget _buildPeriodBar() {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (mode, label) in const [
            (_PeriodMode.today, '今日'),
            (_PeriodMode.thisMonth, '今月'),
            (_PeriodMode.custom, '期間を選ぶ'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _periodMode == mode,
              onSelected: (_) => mode == _PeriodMode.custom
                  ? _pickCustomRange()
                  : _setPeriod(mode),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSummary,
            tooltip: '最新にする',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: '読み込めませんでした',
        message: _errorMessage,
        action: ElevatedButton(
          onPressed: _loadSummary,
          child: const Text('もう一度読み込む'),
        ),
      );
    }
    final data = _data;
    if (data == null) return const SizedBox();

    final r = _range;
    final total = data['total_amount'] as int? ?? 0;
    final count = data['sales_count'] as int? ?? 0;
    final refundCount = data['refund_count'] as int? ?? 0;
    final payments = (data['payment_breakdown'] as Map<String, dynamic>?) ?? {};
    final daily = ((data['daily'] as List?) ?? []).cast<Map<String, dynamic>>();
    final products = ((data['top_products'] as List?) ?? [])
        .cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(r.from == r.to ? r.from : '${r.from} 〜 ${r.to}', yen(total)),
            _kpi('会計の件数', '$count 件'),
            _kpi('客単価', count == 0 ? '-' : yen(total ~/ count)),
            if (refundCount > 0)
              _kpi('返品 $refundCount件', yen(data['refund_total'] as num?)),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '支払い方法',
          child: Column(
            children: [
              for (final e in payments.entries)
                if ((e.value as num? ?? 0) != 0)
                  LabelValue(
                    _paymentLabels[e.key] ?? e.key,
                    yen(e.value as num?),
                    size: 18,
                  ),
              if (payments.values.every((v) => (v as num? ?? 0) == 0))
                const Text('まだ会計がありません'),
            ],
          ),
        ),
        if (daily.length > 1) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: '日ごとの売上',
            child: Column(
              children: [
                for (final d in daily)
                  LabelValue(
                    '${d['date']}（${d['count']}件）',
                    yen(d['amount'] as num?),
                    size: 17,
                  ),
              ],
            ),
          ),
        ],
        if (products.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'よく売れた商品',
            child: Column(
              children: [
                for (final (i, p) in products.indexed)
                  LabelValue(
                    '${i + 1}. ${p['product_name']}（${p['quantity']}個）',
                    yen(p['amount'] as num?),
                    size: 17,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _kpi(String label, String value) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.secondary)),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
