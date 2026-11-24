// 店舗運営の画面（勤怠・棚卸・入荷・予約・厨房など）で共通に使う部品
import 'package:flutter/material.dart';

extension ResultMessage on State {
  /// APIの結果を画面下に表示する
  void showResult(Map<String, dynamic> result, String successMessage) {
    if (!mounted) return;
    final ok = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? successMessage : result['message']?.toString() ?? '処理に失敗しました',
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }
}

/// 日時（ISO8601）を「月/日 時:分」で表示する
String shortTime(Object? value) {
  final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (time == null) return '-';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.month}/${time.day} ${two(time.hour)}:${two(time.minute)}';
}

/// 一覧を読み込んで表示する画面の土台
class ReloadableList extends StatefulWidget {
  const ReloadableList({
    super.key,
    required this.title,
    required this.load,
    required this.listKey,
    required this.itemBuilder,
    this.header,
    this.emptyMessage = 'データがありません',
  });

  final String title;
  final Future<Map<String, dynamic>> Function() load;
  final String listKey;
  final Widget Function(
    BuildContext context,
    Map<String, dynamic> item,
    VoidCallback reload,
  )
  itemBuilder;
  final Widget Function(VoidCallback reload)? header;
  final String emptyMessage;

  @override
  State<ReloadableList> createState() => _ReloadableListState();
}

class _ReloadableListState extends State<ReloadableList> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.load();
    if (!mounted) return;
    setState(() {
      _error = result['success'] == true
          ? null
          : result['message']?.toString() ?? '読み込みに失敗しました';
      _items = ((result[widget.listKey] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (widget.header != null) widget.header!(_load),
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null || items.isEmpty
                ? Center(child: Text(_error ?? widget.emptyMessage))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        widget.itemBuilder(context, items[i], _load),
                  ),
          ),
        ],
      ),
    );
  }
}
