// 店舗運営の画面（勤怠・棚卸・入荷・予約・厨房など）で共通に使う部品
import 'package:material_ui/material_ui.dart';
import 'package:onlipos/ui/common.dart';
import 'package:onlipos/ui/app_header.dart';

extension ResultMessage on State {
  /// APIの結果を画面下に表示する
  void showResult(Map<String, dynamic> result, String successMessage) {
    if (!mounted) return;
    final ok = result['success'] == true;
    showMessage(
      context,
      ok ? successMessage : result['message']?.toString() ?? 'うまくいきませんでした',
      ok ? MessageType.success : MessageType.error,
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
    this.emptyIcon = Icons.inbox_outlined,
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
  final IconData emptyIcon;

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
      appBar: AppHeader(
        widget.title,
        actions: [
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('最新にする'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final header = widget.header?.call(_load);
          final content = _content(items);
          if (header == null) return content;
          // 画面が低いときは、入力欄と一覧をまとめてスクロールする
          return SingleChildScrollView(
            child: Column(
              children: [
                header,
                SizedBox(
                  height: (box.maxHeight - 260).clamp(260, double.infinity),
                  child: content,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _content(List<Map<String, dynamic>>? items) {
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: '読み込めませんでした',
        message: _error,
        action: ElevatedButton(onPressed: _load, child: const Text('もう一度読み込む')),
      );
    }
    if (items.isEmpty) {
      return EmptyState(icon: widget.emptyIcon, title: widget.emptyMessage);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => Card(
        clipBehavior: Clip.antiAlias,
        child: widget.itemBuilder(context, items[i], _load),
      ),
    );
  }
}
