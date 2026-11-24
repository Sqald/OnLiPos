/// 全画面共通のフッター。店舗・営業日・担当者・通信の状態・未送信の会計・時刻を常に表示する。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/operations/failed_sales_view.dart';
import 'package:onlipos/ui/app_session.dart';
import 'package:onlipos/ui/app_theme.dart';

/// どの画面からでも画面遷移できるようにするためのキー
final appNavigatorKey = GlobalKey<NavigatorState>();

/// MaterialApp.builder で使い、すべての画面の下にフッターを付ける
Widget withStatusFooter(BuildContext context, Widget? child) {
  // printing など、まだ material_ui に移行していないパッケージの画面部品へテーマと日本語表示を渡す。
  // それらが移行したら外す
  // ignore: deprecated_member_use
  return MaterialUiCompatibilityBridge(
    child: Builder(builder: (context) => _withFooter(context, child)),
  );
}

Widget _withFooter(BuildContext context, Widget? child) {
  final media = MediaQuery.of(context);
  // 文字入力のキーボードが出ている間は、入力欄を広く使えるように隠す
  if (media.viewInsets.bottom > 0 || media.size.height < 320) {
    return child ?? const SizedBox.shrink();
  }
  return Column(
    children: [
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      const StatusFooter(),
    ],
  );
}

class StatusFooter extends StatefulWidget {
  const StatusFooter({super.key});

  @override
  State<StatusFooter> createState() => _StatusFooterState();
}

class _StatusFooterState extends State<StatusFooter> {
  final _session = AppSession.instance;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _session.loadStore();
    _session.refreshCounts();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _session.refreshCounts();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openFailed() => appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const FailedSalesView()),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 36,
          child: ListenableBuilder(
            listenable: _session,
            builder: (context, _) {
              final now = DateTime.now();
              final date = _session.businessDate;
              String two(int n) => n.toString().padLeft(2, '0');
              return LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 720;
                  return Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          [
                            _session.storeName ?? 'OnLiPos',
                            if (wide && date != null)
                              '営業日 ${date.month}/${date.day}',
                            if (_session.operatorName != null)
                              '業務開始: ${_session.operatorName}',
                          ].join('　｜　'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD6DCE6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_session.failedCount > 0)
                        _chip(
                          Icons.error,
                          '送信できない会計 ${_session.failedCount}件',
                          const Color(0xFFFF9EA3),
                          onTap: _openFailed,
                        ),
                      if (_session.pendingCount > 0)
                        _chip(
                          Icons.cloud_upload,
                          '未送信 ${_session.pendingCount}件',
                          const Color(0xFFFFD479),
                        ),
                      if (_session.online != null)
                        _chip(
                          _session.online! ? Icons.wifi : Icons.wifi_off,
                          _session.online! ? '通信OK' : '通信できません',
                          _session.online!
                              ? const Color(0xFF8FE0B4)
                              : const Color(0xFFFFD479),
                        ),
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            'v${PosApiClient.appVersion}',
                            style: const TextStyle(
                              color: Color(0xFF97A1B1),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const SizedBox(width: 14),
                      Text(
                        '${two(now.hour)}:${two(now.minute)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(color: color, fontSize: 14)),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
