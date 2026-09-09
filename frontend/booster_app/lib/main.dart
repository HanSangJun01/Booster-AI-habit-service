import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/session.dart';
import 'theme/booster_theme.dart';
import 'screens/auth/login_screen.dart';

/// 화면 밖(=BuildContext가 없는 곳)에서 화면 전환이 필요할 때 쓰는 통로.
/// 토큰 만료 처리가 여기에 해당한다 — API 계층에서 감지되는데, 정작 화면 전환은
/// Navigator가 있어야 하기 때문이다.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  ApiClient.onUnauthorized = handleSessionExpired;
  runApp(const BoosterApp());
}

/// 401을 받으면 세션을 비우고 로그인 화면으로 되돌린다.
///
/// 화면 여러 개가 동시에 요청을 날린 상황(예: `Future.wait`)에서는 401이 한꺼번에
/// 여러 번 올라온다. 그때마다 push하면 로그인 화면이 겹쳐 쌓이므로 프레임 단위로
/// 한 번만 처리한다.
bool _redirectingToLogin = false;

void handleSessionExpired() {
  if (_redirectingToLogin) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;

  _redirectingToLogin = true;
  Session.clear();
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen(sessionExpired: true)),
    (route) => false,
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => _redirectingToLogin = false);
}

class BoosterApp extends StatelessWidget {
  const BoosterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Booster',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: BoosterTheme.light(),
      home: const LoginScreen(),
    );
  }
}
