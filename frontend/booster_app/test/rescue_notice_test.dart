// 구제 안내 팝업 검증.
//
// 이 팝업이 없으면 사용자는 새벽에 예고 없이 스트릭 0 + 코인 −500을 맞는다.
// 서버가 2일짜리 유예를 두는 이유가 통째로 사라지는 것이라, 확인할 건 하나다:
// **구제 대기 상태를 사용자에게 제때, 정확히 알리고 결정하게 하는가.**
//
//  1. pendingRescueWeek이 있을 때만 뜬다
//  2. 기한과 양쪽 결과(구제 / 방치)를 보여준다
//  3. 구제하면 POST /api/personal/rescue로 나간다
//  4. 이미 처리됐거나 기한이 지났으면 재시도를 권하지 않고 닫는다
//
//   flutter test test/rescue_notice_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/models/weekly_goal.dart';
import 'package:booster_app/screens/home/rescue_notice.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late List<({String method, String path})> _received;

Map<String, dynamic> _goalJson({
  String? pendingRescueWeek = '2026-08-17',
  String? rescueDeadline = '2026-08-25T23:59:00',
  int lateRescuePrice = 1200,
  int coinBalance = 1500,
}) {
  return {
    'weekStart': '2026-08-24',
    'targetDays': 3,
    'pendingTargetDays': null,
    'successCount': 2,
    'remainingDays': 4,
    'recoveryTickets': 0,
    'freeTickets': 0,
    'paidTickets': 0,
    'ticketPrice': 800,
    'coinBalance': coinBalance,
    'verificationType': 'GPS',
    'lastWeekResult': 'PENDING_RESCUE',
    'pendingRescueWeek': pendingRescueWeek,
    'rescueDeadline': rescueDeadline,
    'lateRescuePrice': lateRescuePrice,
  };
}

late HttpServer _server;

/// 지금 걸려 있는 응답 규칙. [_serveWith]로 테스트마다 갈아끼운다.
///
/// 서버 자체는 setUp에서 띄운다 — `testWidgets` 본문은 FakeAsync 안이라 거기서
/// [HttpServer.bind]를 부르면 서버의 idle 타이머가 가짜 시계에 잡혀 "테스트가
/// 끝났는데 타이머가 남아 있다"로 실패한다.
late void Function(HttpRequest req, String path) _handle;

void _serveWith(void Function(HttpRequest req, String path) handle) =>
    _handle = handle;

void _sendJson(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

/// 실제 통신을 일으키는 동작을 FakeAsync 밖에서 돌린다. 가짜 시계 위에서 시작한
/// 소켓 I/O는 끝나지 않아서, 풀어주지 않으면 버튼이 '구제하는 중…'에 멈춘 채로
/// 검사하게 된다.
Future<void> _withNetwork(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

/// 팝업을 띄우고, 닫힐 때 돌려준 값을 담아둔다.
Future<List<bool>> _pumpNotice(WidgetTester tester, WeeklyGoal goal) async {
  final results = <bool>[];
  await tester.pumpWidget(MaterialApp(
    theme: BoosterTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => results.add(await showRescueNotice(context, goal)),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    _received = [];
    _handle = (req, _) =>
        _sendJson(req, 404, {'success': false, 'message': '요청한 정보를 찾을 수 없습니다'});
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      await utf8.decoder.bind(req).join();
      _received.add((method: req.method, path: req.uri.path));
      _handle(req, req.uri.path);
    });
    ApiClient.overrideBaseUrl('http://${_server.address.host}:${_server.port}/api');

    Session.set(userId: 1, nickname: '테스터', accessToken: 'test-token');
    Session.coinBalance = 1500;
  });

  tearDown(() async {
    ApiClient.overrideBaseUrl(null);
    await _server.close(force: true);
    Session.clear();
  });

  group('띄울 조건', () {
    test('구제 대기 중인 주가 있으면 띄운다', () {
      final goal = WeeklyGoal.fromJson(_goalJson());
      expect(goal.needsRescue, isTrue);
    });

    test('대기 주가 없으면 띄우지 않는다', () {
      final goal = WeeklyGoal.fromJson(_goalJson(pendingRescueWeek: null));
      expect(goal.needsRescue, isFalse);
    });

    test('기한을 모르면 띄우지 않는다', () {
      // "언제까지"를 말할 수 없는 팝업은 사용자가 급한 일인지 판단할 근거를
      // 주지 못한다.
      final goal = WeeklyGoal.fromJson(_goalJson(rescueDeadline: null));
      expect(goal.needsRescue, isFalse);
    });
  });

  group('내용', () {
    testWidgets('기한과 양쪽 결과를 보여준다', (tester) async {
      await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      expect(find.text('지난주 목표를 못 채웠어요'), findsOneWidget);
      expect(find.text('8/17~8/23'), findsOneWidget);
      expect(find.text('목표 3회를 채우지 못했어요'), findsOneWidget);
      expect(find.text('8월 25일 23:59까지 구제할 수 있어요'), findsOneWidget);
      expect(find.text('스트릭 유지 · 코인 차감 없음'), findsOneWidget);
      expect(find.text('스트릭 0 · 코인 500 차감'), findsOneWidget);
    });

    testWidgets('구제 가격은 서버가 준 사후 구매가를 쓴다', (tester) async {
      // 미리 사두는 값(ticketPrice 800)이 아니라 사후 구매가여야 한다.
      await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      expect(find.text('1,200코인으로 구제하기'), findsOneWidget);
      expect(find.text('800코인으로 구제하기'), findsNothing);
    });

    testWidgets('나중에를 누르면 아무것도 보내지 않고 닫힌다', (tester) async {
      _serveWith((req, path) => _sendJson(req, 200, _goalJson()));
      final results = await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();

      expect(find.text('지난주 목표를 못 채웠어요'), findsNothing);
      expect(_received, isEmpty);
      expect(results.single, isFalse);
    });
  });

  group('구제', () {
    testWidgets('구제하기를 누르면 rescue로 나간다', (tester) async {
      _serveWith((req, path) =>
          _sendJson(req, 200, _goalJson(pendingRescueWeek: null, coinBalance: 300)));
      final results = await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      await _withNetwork(
          tester, () => tester.tap(find.text('1,200코인으로 구제하기')));

      expect(_received.single.method, 'POST');
      expect(_received.single.path, '/api/personal/rescue');
      // 잔액은 서버 응답을 따른다.
      expect(Session.coinBalance, 300);
      // 홈이 다시 읽어야 한다는 신호.
      expect(results.single, isTrue);
    });

    testWidgets('이미 처리된 주면 재시도를 권하지 않고 닫는다', (tester) async {
      // 다시 눌러도 같은 답만 돌아온다. 팝업을 열어두면 사용자가 계속 시도한다.
      _serveWith((req, path) => _sendJson(req, 404, {
            'success': false,
            'message': '구제 대기 중인 주가 없습니다',
            'errorCode': 'NO_PENDING_RESCUE',
          }));
      final results = await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      await _withNetwork(
          tester, () => tester.tap(find.text('1,200코인으로 구제하기')));

      expect(find.text('지난주 목표를 못 채웠어요'), findsNothing);
      expect(results.single, isTrue);
    });

    testWidgets('기한이 지났으면 닫는다', (tester) async {
      _serveWith((req, path) => _sendJson(req, 400, {
            'success': false,
            'message': '구제 기한이 지났습니다',
            'errorCode': 'RESCUE_DEADLINE_PASSED',
          }));
      final results = await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      await _withNetwork(
          tester, () => tester.tap(find.text('1,200코인으로 구제하기')));

      expect(find.text('지난주 목표를 못 채웠어요'), findsNothing);
      expect(results.single, isTrue);
    });

    testWidgets('잔액이 모자라면 팝업을 열어둔 채 이유를 알린다', (tester) async {
      // 코인을 벌어서 다시 시도할 수 있는 상황이다. 여기서 닫아버리면 기한
      // 안에 다시 열 방법이 홈 재진입뿐이다.
      _serveWith((req, path) => _sendJson(req, 400, {
            'success': false,
            'message': '코인이 부족합니다',
            'errorCode': 'INSUFFICIENT_COIN',
          }));
      await _pumpNotice(tester, WeeklyGoal.fromJson(_goalJson()));

      await _withNetwork(
          tester, () => tester.tap(find.text('1,200코인으로 구제하기')));

      expect(find.text('지난주 목표를 못 채웠어요'), findsOneWidget);
      expect(find.text('코인이 부족합니다'), findsOneWidget);
      expect(find.text('1,200코인으로 구제하기'), findsOneWidget);
    });
  });
}
