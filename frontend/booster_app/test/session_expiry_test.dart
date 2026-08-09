// 토큰 만료(401) 처리 검증.
//
// 네트워크 계층은 스텁 서버에 실제 HTTP를 태워서 확인하고, 화면 전환은 위젯
// 테스트로 확인한다. 실제 백엔드는 필요 없다 — 확인하려는 건 앱의 반응이지
// 서버의 동작이 아니기 때문이다.
//
// 스텁 서버가 떠 있어야 하는 테스트는 서버가 없으면 skip된다:
//   python3 <scratchpad>/stub_server.py
//   flutter test --dart-define=API_BASE_URL=http://localhost:8080/api

import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/main.dart';
import 'package:booster_app/screens/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _stubBase = 'http://localhost:8080';

Future<bool> _stubAlive() async {
  try {
    await http
        .get(Uri.parse('$_stubBase/__stub/ok'))
        .timeout(const Duration(seconds: 2));
    return true;
  } catch (_) {
    return false;
  }
}

/// 스텁이 없으면 테스트를 skip으로 표시한다.
///
/// `skip:` 인자는 그룹 선언 시점(=await 불가)에 평가돼서 쓸 수 없다.
Future<bool> _requireStub() async {
  if (await _stubAlive()) return true;
  markTestSkipped('스텁 서버(:8080)가 떠 있지 않아 건너뜀');
  return false;
}

Future<void> _setMode(String mode) async {
  final res = await http.get(Uri.parse('$_stubBase/__stub/$mode'));
  if (res.statusCode != 200) {
    throw StateError('스텁 모드 전환 실패: $mode (${res.statusCode})');
  }
}

void main() {
  group('ApiClient 401 판정', () {
    var unauthorizedCalls = 0;

    setUpAll(() {
      // flutter_test는 기본적으로 모든 HTTP를 가로채 400으로 돌려준다.
      // 스텁 서버에 실제로 붙어야 하므로 해제한다.
      HttpOverrides.global = null;
    });

    setUp(() {
      unauthorizedCalls = 0;
      ApiClient.onUnauthorized = () => unauthorizedCalls++;
      Session.accessToken = 'stub-token';
    });

    tearDown(() {
      ApiClient.onUnauthorized = null;
      Session.clear();
    });

    test('만료 토큰 401 → onUnauthorized 호출', () async {
      if (!await _requireStub()) return;
      await _setMode('expired');

      await expectLater(
        ApiClient.get('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.errorCode, 'errorCode', 'UNAUTHORIZED')
            .having((e) => e.isUnauthorized, 'isUnauthorized', true)),
      );
      expect(unauthorizedCalls, 1);
    });

    test('로그인 실패 401 → onUnauthorized 호출 안 함', () async {
      if (!await _requireStub()) return;
      // /auth/** 는 제외해야 한다. 안 그러면 비밀번호 오타가 로그인 화면
      // 재진입을 유발해서 사용자가 로그인을 아예 못 한다.
      await _setMode('badlogin');

      await expectLater(
        ApiClient.post('/auth/login', body: {'email': 'a@b.c', 'password': 'wrong'}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.errorCode, 'errorCode', 'INVALID_CREDENTIALS')),
      );
      expect(unauthorizedCalls, 0);
    });

    test('메시지 없는 5xx → 상태코드 기반 문구', () async {
      if (!await _requireStub()) return;
      await _setMode('error500');

      await expectLater(
        ApiClient.get('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('서버에 문제가 발생했어요'))),
      );
      expect(unauthorizedCalls, 0);
    });

    test('응답 지연 → 연결 실패와 구분된 문구', () async {
      if (!await _requireStub()) return;
      await _setMode('slow');

      await expectLater(
        ApiClient.get('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('응답이 너무 늦어요'))),
      );

      await _setMode('ok');
    },
        timeout: const Timeout(Duration(seconds: 60)));
  });

  group('만료 시 화면 복귀', () {
    tearDown(() => Session.clear());

    testWidgets('세션을 비우고 안내와 함께 로그인 화면으로 돌아간다', (tester) async {
      Session.set(userId: 1, nickname: '테스터', accessToken: 'stub-token');
      Session.coinBalance = 500;

      await tester.pumpWidget(const BoosterApp());
      await tester.pumpAndSettle();

      // main()은 runApp까지 실행돼서 테스트에서 부를 수 없다. main()이 훅으로
      // 등록하는 그 함수를 직접 호출해 401 도달 시점을 재현한다.
      handleSessionExpired();
      await tester.pumpAndSettle();

      expect(Session.isLoggedIn, isFalse);
      expect(Session.accessToken, isNull);
      expect(Session.coinBalance, 0);
      expect(find.text('로그인이 만료됐어요. 다시 로그인해주세요'), findsOneWidget);
    });

    testWidgets('401이 동시에 여러 번 와도 로그인 화면은 하나만 쌓인다', (tester) async {
      Session.set(userId: 1, nickname: '테스터', accessToken: 'stub-token');

      await tester.pumpWidget(const BoosterApp());
      await tester.pumpAndSettle();

      // home_screen은 Future.wait로 4개를 동시에 부른다. 토큰이 만료돼 있으면
      // 401이 한 프레임 안에 네 번 올라온다.
      handleSessionExpired();
      handleSessionExpired();
      handleSessionExpired();
      handleSessionExpired();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
