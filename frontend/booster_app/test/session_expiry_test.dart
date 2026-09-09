// 토큰 만료(401) 처리 검증.
//
// 네트워크 계층은 실제 HTTP를 태워서 확인하고, 화면 전환은 위젯 테스트로
// 확인한다. 확인하려는 건 앱의 반응이지 서버의 동작이 아니다.
//
// 서버는 각 테스트가 직접 띄운다. 외부에 뭘 실행해둘 필요가 없고, 빈 포트를
// 받아 뜨므로 진짜 백엔드(:8080)와 부딪히지도 않는다.
//
//   flutter test

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/main.dart';
import 'package:booster_app/screens/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// [handle]로 응답하는 임시 서버를 띄우고 [ApiClient]가 그리로 향하게 한다.
///
/// 서버 종료와 주소 복구는 [addTearDown]으로 걸어두므로 호출한 쪽이 정리를
/// 신경 쓸 필요가 없다.
Future<void> _serveWith(void Function(HttpRequest req) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handle);
  ApiClient.overrideBaseUrl('http://${server.address.host}:${server.port}/api');

  addTearDown(() async {
    ApiClient.overrideBaseUrl(null);
    await server.close(force: true);
  });
}

/// 백엔드 `GlobalExceptionHandler`가 내려주는 에러 엔벨로프를 흉내낸다.
///
/// Content-Type에 charset을 붙이지 않는다 — 백엔드가 그렇고, 그래야 앱이
/// bodyBytes를 직접 UTF-8로 읽는 경로를 실제로 태운다. charset을 붙이면
/// 한글 깨짐 회귀를 이 테스트가 못 잡는다.
void _sendError(HttpRequest req, int status, String message, String? errorCode) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode({
    'success': false,
    'message': message,
    if (errorCode != null) 'errorCode': errorCode,
  })));
  req.response.close();
}

void main() {
  group('ApiClient 401 판정', () {
    var unauthorizedCalls = 0;

    setUpAll(() {
      // flutter_test는 기본적으로 모든 HTTP를 가로채 400으로 돌려준다.
      // 테스트 서버에 실제로 붙어야 하므로 해제한다.
      HttpOverrides.global = null;
    });

    setUp(() {
      unauthorizedCalls = 0;
      ApiClient.onUnauthorized = () => unauthorizedCalls++;
      Session.accessToken = 'test-token';
    });

    tearDown(() {
      ApiClient.onUnauthorized = null;
      Session.clear();
    });

    test('만료 토큰 401 → onUnauthorized 호출', () async {
      await _serveWith((req) => _sendError(req, 401, '인증이 필요합니다.', 'UNAUTHORIZED'));

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
      // /auth/** 는 제외해야 한다. 안 그러면 비밀번호 오타가 로그인 화면
      // 재진입을 유발해서 사용자가 로그인을 아예 못 한다.
      await _serveWith((req) => _sendError(
          req, 401, '이메일 또는 비밀번호가 올바르지 않습니다.', 'INVALID_CREDENTIALS'));

      await expectLater(
        ApiClient.post('/auth/login', body: {'email': 'a@b.c', 'password': 'wrong'}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.errorCode, 'errorCode', 'INVALID_CREDENTIALS')),
      );
      expect(unauthorizedCalls, 0);
    });

    test('메시지 없는 5xx → 상태코드 기반 문구', () async {
      // 프록시 에러 페이지처럼 JSON이 아닌 5xx. 앱이 상태 코드만 보고
      // 문구를 만들어야 한다.
      await _serveWith((req) {
        req.response.statusCode = 500;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body>Internal Server Error</body></html>');
        req.response.close();
      });

      await expectLater(
        ApiClient.get('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', contains('서버에 문제가 발생했어요'))),
      );
      expect(unauthorizedCalls, 0);
    });

    test('응답 지연 → 연결 실패와 구분된 문구', () async {
      // 서버에 닿긴 했는데 제때 답이 없는 경우. "연결할 수 없다"와 원인이
      // 달라서(과부하 vs 주소·방화벽) 문구가 구분돼야 한다.
      // 응답을 아예 주지 않으면 앱의 15초 타임아웃이 걸린다.
      await _serveWith((req) {/* 응답하지 않는다 */});

      await expectLater(
        ApiClient.get('/users/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('응답이 너무 늦어요'))),
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('만료 시 화면 복귀', () {
    tearDown(() => Session.clear());

    testWidgets('세션을 비우고 안내와 함께 로그인 화면으로 돌아간다', (tester) async {
      Session.set(userId: 1, nickname: '테스터', accessToken: 'test-token');
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
      Session.set(userId: 1, nickname: '테스터', accessToken: 'test-token');

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
