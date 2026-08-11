/// ジャーナル一覧画面。「ジャーナル閲覧」権限を持つ担当者コード＋パスワードで
/// 認証したうえで、日付・端末・種別でフィルタしたジャーナル一覧を表示する。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/journal/journal_api.dart';
import 'package:onlipos/journal/journal_detail_view.dart';
import 'package:onlipos/login/login_api.dart';

class JournalListView extends StatefulWidget {
  const JournalListView({super.key});

  @override
  State<JournalListView> createState() => _JournalListViewState();
}

class _JournalListViewState extends State<JournalListView> {
  // 認証フェーズ
  bool _authenticated = false;
  bool _isAuthenticating = false;
  int? _employeeId;
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  // フィルタ
  DateTime _selectedDate = DateTime.now();
  String? _selectedType;
  int? _currentPosId;
  String _currentPosName = '';

  // データ
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _entries = [];

  static const _types = [
    (null, '全種別'),
    ('sale', '売上'),
    ('refund', '返品'),
    ('register_open', 'レジ開設'),
    ('cash_check', 'レジ金確認'),
    ('cash_pickup', '途中回収'),
    ('register_close', 'レジ精算'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPosInfo();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // 現在使用中のPOS端末情報をSecureStorageから取得する
  Future<void> _loadPosInfo() async {
    final pos = await JournalApi.currentPos();
    if (mounted) {
      setState(() {
        _currentPosId = pos.posId;
        _currentPosName = pos.posName;
      });
    }
  }

  // 担当者コード・パスワードで認証し、ジャーナル閲覧権限を確認する
  Future<void> _authenticate() async {
    final code = _codeCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (code.isEmpty || pin.isEmpty) {
      _showError('担当者コードとパスワードを入力してください');
      return;
    }
    setState(() => _isAuthenticating = true);
    try {
      final result = await LoginApi.verifyEmployee(code: code, pin: pin);
      if (!mounted) return;
      if (result['success'] == true) {
        final perms = (result['permissions'] as List?)?.cast<String>() ?? [];
        if (!perms.contains('view_journal')) {
          setState(() => _isAuthenticating = false);
          _showError('ジャーナル閲覧権限がありません');
          return;
        }
        setState(() {
          _authenticated = true;
          _employeeId = result['employee_id'] as int?;
          _isAuthenticating = false;
        });
        _loadEntries();
      } else {
        setState(() => _isAuthenticating = false);
        _showError(result['message']?.toString() ?? '認証に失敗しました');
      }
    } catch (_) {
      if (mounted) setState(() => _isAuthenticating = false);
      _showError('認証中にエラーが発生しました');
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

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ジャーナル')),
      body: _authenticated ? _buildMain() : _buildAuth(),
    );
  }

  // ── 認証画面 ──────────────────────────────────────────────────────────────

  // 担当者コード・パスワード入力フォームを表示する
  Widget _buildAuth() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '「ジャーナル閲覧」権限が必要です',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '担当者コード',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinCtrl,
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

  // 端末表示・日付選択・種別チップからなるフィルタバーを組み立てる
  Widget _buildFilterBar() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '端末: ',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              Text(
                _currentPosName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateStr(_selectedDate)),
                onPressed: _pickDate,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadEntries,
                tooltip: '再読み込み',
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _types.map((t) {
                final selected = _selectedType == t.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t.$2),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedType = t.$1);
                      _loadEntries();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 読み込み状態・エラー・空状態を考慮したジャーナル一覧を表示する
  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadEntries, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('ジャーナルが見つかりません'));
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final e = _entries[index];
        return ListTile(
          leading: _TypeIcon(e['entry_type'] as String? ?? ''),
          title: Text(_entryTypeLabel(e['entry_type'] as String? ?? '')),
          subtitle: Text(
            [
              _fmtTime(e['printed_at'] as String? ?? ''),
              if (e['employee_name'] != null) '担当: ${e['employee_name']}',
            ].join('  '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (e['receipt_number'] != null)
                Text(
                  e['receipt_number'].toString(),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              if (e['amount'] != null)
                Text(
                  '¥${_fmt((e['amount'] as num).toInt())}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    JournalDetailView(employeeId: _employeeId!, summary: e),
              ),
            );
          },
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
  'cash_check' => 'レジ金確認',
  'cash_pickup' => '途中回収',
  'register_close' => 'レジ精算',
  _ => type,
};

// 金額を3桁区切りのカンマ付き文字列に整形する
String _fmt(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

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
