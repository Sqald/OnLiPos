import 'package:flutter/material.dart';
import 'package:onlipos/login/login_top_view.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'dart:io';

// sqflite_common_ffiをインポート
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// flutter_secure_storageをインポート
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // 追加: kIsWebの判定用

void main() async {
  // Flutterのバインディングを初期化（非同期処理の前に必須）
  WidgetsFlutterBinding.ensureInitialized();

  // デスクトップ環境向けにsqflite_common_ffiを初期化
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  const storage = FlutterSecureStorage();
  final loginToken = await storage.read(key: 'LoginToken');

  Widget initialView;
  if (loginToken == null) {
    initialView = const SetupPage(title: '初期設定');
  } else {
    initialView = const LoginTopView();
  }

  // ----------------------------------------------------
  // デスクトップ(Windows/macOS/Linux)向けのキオスクモード(完全全画面)設定
  // ----------------------------------------------------
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      title: 'OnliPos Client',
      center: true,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true); 
    });
  }

  // Androidなどのモバイル向けの全画面＆横画面固定設定（これは全プラットフォームで実行してOK）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(MyApp(initialView: initialView));
}

class MyApp extends StatelessWidget {
  final Widget initialView;
  const MyApp({super.key, required this.initialView});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnliPos Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), // 修正: ColorSchemeを明記
      ),
      home: initialView,
    );
  }
}