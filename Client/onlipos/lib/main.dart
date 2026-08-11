/// アプリのエントリポイント。
/// 起動直後は空の`runApp`でUIを先に表示し、その後バックグラウンドで
/// ログイントークンの有無を確認して初回セットアップ画面かログイン画面かを振り分ける。
/// デスクトップ環境ではウィンドウの全画面化、モバイル環境では横画面固定も行う。
library;

import 'package:flutter/material.dart';
import 'package:onlipos/login/login_top_view.dart';
import 'package:onlipos/setup/setup_view.dart';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is AssertionError &&
        error.message.toString().contains('data.physical != 0')) {
      return true;
    }
    return false;
  };

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 修正ポイント1: main()で待機せず、速攻でrunAppを呼んでWindowsに正常なアプリだと認識させる
  runApp(const MyApp());
}

/// アプリのルートウィジェット。初期表示先(セットアップ/ログイン)が決まるまでは
/// ローディング表示を出し、非同期で初期化を行う。
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Widget? initialView;

  // Widget構築後に非同期初期化処理を開始する
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // 修正ポイント2: アプリのUIが起動した"後"に裏で設定を読み込む
  Future<void> _initializeApp() async {
    // 1. ストレージの読み込み
    const storage = FlutterSecureStorage();
    final loginToken = await storage.read(key: 'LoginToken');

    if (mounted) {
      setState(() {
        if (loginToken == null) {
          initialView = const SetupPage(title: '初期設定');
        } else {
          initialView = const LoginTopView();
        }
      });
    }

    // 2. デスクトップ向けのウィンドウ設定
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        title: 'OnliPos Client',
        center: true,
        skipTaskbar: false,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        // 修正ポイント3: ゴースト化を防ぐため、一呼吸（300ミリ秒）置いてから全画面化する
        await Future.delayed(const Duration(milliseconds: 300));
        await windowManager.setFullScreen(true);
      });
    }

    // 3. モバイル向けの全画面＆横画面固定設定
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  // 初期画面が確定するまではローディング表示、確定後は該当画面をhomeに設定する
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OnliPos Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // initialViewが決まるまではローディングインジケーターを出しておく
      home:
          initialView ??
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
