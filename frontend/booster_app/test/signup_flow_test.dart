// 회원가입 경로 검증.
//
// 서버(`integration/a-b-axis`)의 `SignupResponse`는 accessToken까지 준다. 그래서
// 가입은 요청 한 번으로 끝나야 하고, 로그인을 다시 부르면 BCrypt가 두 번 돈다.
// 토큰을 안 주는 옛 계약을 만났을 때만 로그인으로 넘어가는데, 그 두 번째 호출이
// 실패하면 계정은 이미 만들어진 채 앱만 실패한 것처럼 굴어서 사용자가 같은
// 이메일로 재시도하다 중복 409에 갇힌다. 두 경로를 모두 본다.
//
// 네트워크 계층은 임시 서버를 띄워 실제 HTTP로 확인하고, 화면 반응은 위젯
// 테스트로 확인한다. testWidgets 안에서는 서버를 띄우지 않는다 — fake async가
// HttpServer의 idleTimeout을 가짜 타이머로 만들어 pumpAndSettle이 "Pending
// timers"로 죽는다(`team_create_test.dart` 참조).
//
//   flutter test test/signup_flow_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/screens/auth/login_screen.dart';
import 'package:booster_app/screens/auth/signup_screen.dart';
import 'package:booster_app/services/auth_service.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:booster_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 임시 서버가 받은 요청 본문을 경로별로 모아둔다.
final _received = <String, Map<String, dynamic>>{};

/// [handle]로 응답하는 임시 서버를 띄우고 [ApiClient]가 그리로 향하게 한다.
///
/// 본문을 먼저 읽어 [_received]에 담으므로, 앱이 무엇을 보냈는지도 검증할 수
/// 있다. 정리는 [addTearDown]으로 걸어둔다.
Future<void> _serveWith(void Function(HttpRequest req) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = await utf8.decodeStream(req);
    if (body.isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) _received[req.uri.path] = decoded;
    }
    handle(req);
  });
  ApiClient.overrideBaseUrl('http://${server.address.host}:${server.port}/api');

  addTearDown(() async {
    ApiClient.overrideBaseUrl(null);
    await server.close(force: true);
  });
}

void _sendJson(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  // charset을 붙이지 않는다 — 백엔드가 그렇고, 그래야 앱이 bodyBytes를 직접
  // UTF-8로 읽는 경로를 실제로 태운다.
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

/// A축 가입 성공 응답(DTO 그대로). 실제 계약대로 accessToken을 함께 준다.
Map<String, dynamic> _signupOk({int? coinBalance = 500, String? accessToken = 'test-token'}) => {
      'userId': 1,
      'email': 'user@example.com',
      'nickname': '부스터',
      if (accessToken != null) 'accessToken': accessToken,
      if (coinBalance != null) 'coinBalance': coinBalance,
      'joinedAt': '2026-08-29T10:00:00',
    };

Map<String, dynamic> get _loginOk => {
      'userId': 1,
      'email': 'user@example.com',
      'nickname': '부스터',
      'accessToken': 'test-token',
    };

/// 가입 화면의 제출 버튼. 상단 타이틀도 '회원가입'이라 텍스트만으로는 못 고른다.
final _submitButton = find.descendant(
    of: find.byType(PrimaryButton), matching: find.text('회원가입'));

/// 로그인 화면의 가입 링크. 한 RichText 안에 안내 문구와 함께 들어 있어서
/// 기본 [find.text]로는 안 잡힌다.
final _signupLink = find.textContaining('아직 계정이 없으신가요', findRichText: true);

Future<void> _pumpLogin(WidgetTester tester, {String? signedUpEmail}) async {
  await tester.pumpWidget(MaterialApp(
    theme: BoosterTheme.light(),
    home: LoginScreen(signedUpEmail: signedUpEmail),
  ));
  await tester.pumpAndSettle();
}

/// flutter_test가 기본으로 깔아두는 HTTP 가로채기.
///
/// 임시 서버에 실제로 붙어야 하는 test() 그룹에서는 이걸 벗기고, 위젯 테스트에서는
/// 도로 씌운다. 안 씌우면 화면이 보낸 요청이 진짜 소켓을 잡으러 나가 응답 없이
/// 15초 타임아웃 타이머를 남기고, pumpAndSettle이 "Pending timers"로 죽는다.
HttpOverrides? _testHttpOverrides;

void main() {
  setUpAll(() {
    _testHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  setUp(_received.clear);
  tearDown(Session.clear);

  group('가입 후 자동 로그인', () {
    test('토큰이 오면 로그인을 다시 부르지 않는다', () async {
      // 서버가 토큰을 주는데도 로그인을 또 부르면 BCrypt가 두 번 돈다.
      await _serveWith((req) => _sendJson(
          req, 201, req.uri.path.endsWith('/auth/signup') ? _signupOk() : _loginOk));

      await AuthService.signup('부스터', 'user@example.com', 'password1234');

      expect(_received.containsKey('/api/auth/login'), isFalse);
      expect(Session.isLoggedIn, isTrue);
      expect(Session.accessToken, 'test-token');
      expect(Session.coinBalance, 500);
    });

    test('토큰이 없으면 로그인으로 이어간다', () async {
      // 옛 계약 폴백. 이 경로가 살아 있어야 토큰 없는 서버에서도 가입이 끝난다.
      await _serveWith((req) => _sendJson(
          req,
          201,
          req.uri.path.endsWith('/auth/signup')
              ? _signupOk(accessToken: null)
              : _loginOk));

      await AuthService.signup('부스터', 'user@example.com', 'password1234');

      expect(_received.containsKey('/api/auth/login'), isTrue);
      expect(Session.accessToken, 'test-token');
    });

    test('폴백 로그인이 실패해도 "가입 실패"로 뭉뚱그리지 않는다', () async {
      // 계정은 이미 만들어졌다. ApiException으로 올리면 화면이 가입 실패로
      // 안내하고, 사용자는 재시도하다 이메일 중복 409만 보게 된다.
      await _serveWith((req) {
        if (req.uri.path.endsWith('/auth/signup')) {
          _sendJson(req, 201, _signupOk(accessToken: null));
        } else {
          _sendJson(req, 500,
              {'success': false, 'message': '서버에 문제가 발생했어요.', 'errorCode': 'INTERNAL'});
        }
      });

      await expectLater(
        AuthService.signup('부스터', 'user@example.com', 'password1234'),
        throwsA(isA<SignupAutoLoginException>()
            .having((e) => e.email, 'email', 'user@example.com')),
      );
      // 로그인은 실패했으므로 세션은 비어 있어야 한다.
      expect(Session.isLoggedIn, isFalse);
      expect(Session.accessToken, isNull);
    });

    test('가입 응답에 잔액이 없으면 0으로 덮지 않는다', () async {
      // 실제 서버는 coinBalance를 주지만(`SignupResponse`), 스펙 문서(§4.1)에는
      // 없다. 계약이 어긋나 빠져도 0으로 메우면 안 된다 — 가입 보너스가 화면에서
      // 사라진 것처럼 보인다.
      Session.coinBalance = 500;
      await _serveWith((req) => _sendJson(
          req,
          200,
          req.uri.path.endsWith('/auth/signup')
              ? _signupOk(coinBalance: null)
              : _loginOk));

      await AuthService.signup('부스터', 'user@example.com', 'password1234');

      expect(Session.coinBalance, 500);
    });
  });

  group('이메일 정규화', () {
    test('가입과 로그인이 같은 형태로 보낸다', () async {
      // 가입할 때 대문자로 적은 사람이 다음 로그인에서 소문자를 치면, 서버가
      // 대소문자를 구분하는 순간 "없는 계정"이 된다. 서버는 정규화하지 않으므로
      // (`AuthService.findByEmail` 그대로) 앱이 양쪽을 같은 형태로 맞춰야 한다.
      await _serveWith((req) => _sendJson(
          req, 201, req.uri.path.endsWith('/auth/signup') ? _signupOk() : _loginOk));

      await AuthService.signup('부스터', '  User@Example.COM ', 'password1234');
      expect(_received['/api/auth/signup']!['email'], 'user@example.com');

      // 로그인은 가입과 별개 호출이다(토큰이 오면 가입이 로그인을 부르지 않는다).
      await AuthService.login(' USER@example.com  ', 'password1234');
      expect(_received['/api/auth/login']!['email'], 'user@example.com');
    });

    test('닉네임 앞뒤 공백은 잘라서 보낸다', () async {
      await _serveWith((req) => _sendJson(
          req, 200, req.uri.path.endsWith('/auth/signup') ? _signupOk() : _loginOk));

      await AuthService.signup('  부스터  ', 'user@example.com', 'password1234');

      expect(_received['/api/auth/signup']!['nickname'], '부스터');
    });
  });

  group('에러 문구', () {
    test('엔벨로프가 아니어도 한글 메시지는 그대로 보여준다', () async {
      // GlobalExceptionHandler를 타지 않는 400(스프링 기본 검증 등)은 success
      // 키가 없다. 메시지를 버리면 어느 칸이 문제인지 알려줄 수 없다.
      await _serveWith((req) => _sendJson(req, 400, {
            'status': 400,
            'error': 'Bad Request',
            'message': '닉네임은 30자를 넘을 수 없습니다.',
          }));

      await expectLater(
        ApiClient.post('/auth/signup', body: {'email': 'a@b.c'}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '닉네임은 30자를 넘을 수 없습니다.')),
      );
    });

    test('영문 기본 문구는 안내로 쓰지 않는다', () async {
      // "Validation failed for object..."를 그대로 띄우면 안내가 아니라 잡음이다.
      await _serveWith((req) => _sendJson(req, 400, {
            'status': 400,
            'error': 'Bad Request',
            'message': 'Validation failed for object=\'signupRequest\'',
          }));

      await expectLater(
        ApiClient.post('/auth/signup', body: {'email': 'a@b.c'}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('요청 처리 중 오류'))),
      );
    });
  });

  group('회원가입 화면 검증', () {
    // 가로채기를 씌워두면 화면이 보낸 요청은 즉시 400으로 끝난다 — 실제 서버를
    // 찾아 나가지 않으므로 타이머가 남지 않는다.
    setUp(() => HttpOverrides.global = _testHttpOverrides);
    tearDown(() => HttpOverrides.global = null);

    testWidgets('닉네임이 30자를 넘으면 요청 전에 막는다', (tester) async {
      // 서버 제약이 1~30자다. 안 막으면 400으로 튕기고 사용자는 이유를 모른다.
      await tester.pumpWidget(MaterialApp(
        theme: BoosterTheme.light(),
        home: const SignupScreen(),
      ));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'ㄱ' * 31);
      await tester.enterText(fields.at(1), 'user@example.com');
      await tester.enterText(fields.at(2), 'password1234');
      await tester.enterText(fields.at(3), 'password1234');
      await tester.tap(_submitButton);
      await tester.pumpAndSettle();

      expect(find.text('닉네임은 30자를 넘을 수 없어요'), findsOneWidget);
      // 화면이 그대로여야 한다 — 요청이 나갔다면 로딩 문구로 바뀐다.
      expect(find.text('가입 중...'), findsNothing);
    });

    testWidgets('30자까지는 통과시킨다', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: BoosterTheme.light(),
        home: const SignupScreen(),
      ));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'ㄱ' * 30);
      await tester.enterText(fields.at(1), 'user@example.com');
      await tester.enterText(fields.at(2), 'password1234');
      await tester.enterText(fields.at(3), 'password1234');
      await tester.tap(_submitButton);
      await tester.pumpAndSettle();

      expect(find.text('닉네임은 30자를 넘을 수 없어요'), findsNothing);
      // 검증을 통과해 요청까지 갔다는 증거. 가로채기가 400으로 끊어주므로
      // 화면에는 서버 오류 문구가 남는다.
      expect(find.text('요청 처리 중 오류가 발생했습니다'), findsOneWidget);
    });
  });

  group('자동 로그인 실패 후 안내', () {
    setUp(() => HttpOverrides.global = _testHttpOverrides);
    tearDown(() => HttpOverrides.global = null);

    testWidgets('로그인 화면이 이메일을 채우고 가입 완료를 알린다', (tester) async {
      await _pumpLogin(tester, signedUpEmail: 'user@example.com');

      expect(find.text('가입은 완료됐어요. 비밀번호를 입력해 로그인해주세요'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
    });

    testWidgets('가입 화면이 이메일을 들고 돌아오면 그대로 이어받는다', (tester) async {
      await _pumpLogin(tester);

      await tester.tap(_signupLink);
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);

      // SignupScreen이 SignupAutoLoginException을 받았을 때 하는 일과 같다.
      tester.state<NavigatorState>(find.byType(Navigator)).pop('user@example.com');
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('가입은 완료됐어요. 비밀번호를 입력해 로그인해주세요'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
    });
  });
}
