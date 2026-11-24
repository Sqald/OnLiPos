/// ジャーナル一覧画面。「ジャーナル閲覧」権限を持つ担当者コード＋パスワードで
/// 認証したうえで、日付・端末・種別でフィルタしたジャーナル一覧を表示する。
library;

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_theme.dart';
import 'package:onlipos/ui/app_header.dart';
import 'package:onlipos/login/operator_sign_in_panel.dart';
import 'package:onlipos/journal/journal_api.dart';
import 'package:onlipos/journal/journal_detail_view.dart';

class JournalListView extends StatefulWidget {
  const JournalListView({super.key});

  @override
  State<JournalListView> createState() => _JournalListViewState();
}

class _JournalListViewState extends State<JournalListView> {
  // 認証フェーズ
  bool _authenticated = false;
  int? _employeeId;

  // フィルタ
  DateTime _selectedDate = DateTime.now();
  String? _selectedType;
  int? _currentPosId;

  // データ
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _entries = [];

  static const _types = [
    (null, '全種別'),
    ('sale', '売上'),
    ('refund', '返品'),
    ('register_open', 'レジ開設'),
    ('cash_check', 'レジ金の点検'),
    ('cash_pickup', '途中回収'),
    ('register_close', 'レジ精算'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPosInfo();
  }

  // 現在使用中のPOS端末情報をSecureStorageから取得する
  Future<void> _loadPosInfo() async {
    final pos = await JournalApi.currentPos();
    if (mounted) {
      setState(() {
        _currentPosId = pos.posId;
      });
    }
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // 選択中の日付・端末・種別条件でジャーナル一覧を取得する
  Future<void> _loadEntries() async {
    final eid = _employeeId;
    if (eid == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await JournalApi.fetchList(
      employeeId: eid,
      posId: _currentPosId,
      date: _dateStr(_selectedDate),
      type: _selectedType,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _entries = (result['entries'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result['message']?.toString() ?? 'エラーが発生しました';
        _isLoading = false;
      });
    }
  }

  // 日付選択ダイアログを表示し、選択された日付で再検索する
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader('ジャーナル'),
      body: _authenticated
          ? _buildMain()
          : OperatorSignInPanel(
              icon: Icons.menu_book,
              message: 'ジャーナル（取引の控え）を見るには、「ジャーナル閲覧」の権限を持つ人の確認が必要です。',
              permission: 'view_journal',
              onAuthenticated: (id, name) {
                setState(() {
                  _authenticated = true;
                  _employeeId = id;
                });
                _loadEntries();
              },
            ),
    );
  }

  // ── メイン画面 ────────────────────────────────────────────────────────────

  // フィルタバーと一覧を縦に並べる
  Widget _buildMain() {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(child: _buildList()),
      ],
    );
  }

  // 日付・種類を選ぶ欄
  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(_dateStr(_selectedDate)),
            onPressed: _pickDate,
          ),
          for (final t in _types)
            ChoiceChip(
              label: Text(t.$2),
              selected: _selectedType == t.$1,
              onSelected: (_) {
                setState(() => _selectedType = t.$1);
                _loadEntries();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEntries,
            tooltip: '最新にする',
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: '読み込めませんでした',
        message: _error,
        action: ElevatedButton(
          onPressed: _loadEntries,
          child: const Text('もう一度読み込む'),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'この日の記録はありません',
        message: '日付や種類を変えてみてください',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final e = _entries[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: _TypeIcon(e['entry_type'] as String? ?? ''),
            title: Text(
              '${_fmtTime(e['printed_at'] as String? ?? '')}　${_entryTypeLabel(e['entry_type'] as String? ?? '')}',
            ),
            subtitle: Text(
              [
                if (e['receipt_number'] != null) '${e['receipt_number']}',
                if (e['employee_name'] != null) '担当: ${e['employee_name']}',
              ].join('　'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e['amount'] != null)
                  Text(
                    yen(e['amount'] as num?),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    JournalDetailView(employeeId: _employeeId!, summary: e),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── アイコン ──────────────────────────────────────────────────────────────────

class _TypeIcon extends StatelessWidget {
  final String type;
  const _TypeIcon(this.type);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'sale' => (Icons.receipt, const Color(0xFF2D89EF)),
      'refund' => (Icons.replay, Colors.pink),
      'register_open' => (Icons.lock_open, Colors.green),
      'cash_check' => (Icons.account_balance_wallet, Colors.orange),
      'cash_pickup' => (Icons.move_to_inbox, const Color(0xFFE65100)),
      'register_close' => (Icons.lock, Colors.red),
      _ => (Icons.article, Colors.grey),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ── ユーティリティ ─────────────────────────────────────────────────────────────

// ジャーナル種別コードを日本語ラベルに変換する
String _entryTypeLabel(String type) => switch (type) {
  'sale' => '売上',
  'refund' => '返品',
  'register_open' => 'レジ開設',
  'cash_check' => 'レジ金の点検',
  'cash_pickup' => '途中回収',
  'register_close' => 'レジ精算',
  _ => type,
};

// ISO8601文字列を"HH:mm"形式のローカル時刻表示に変換する
String _fmtTime(String iso) {
  if (iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
