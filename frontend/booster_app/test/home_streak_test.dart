// 홈 화면의 스트릭 표기 검증.
//
// 스트릭은 **연속 일수가 아니라 누적 인증 횟수다.** 인증할 때마다 +1이고 날짜가
// 하루 비어도 끊기지 않는다 — 초기화는 주간 목표 미달이 FAILED로 확정될 때만
// 일어난다(계획서 §3.6). 그래서 "7일 연속" 같은 문구는 앱이 사용자에게 거짓말을
// 하는 것이 된다: 하루 걸러 인증해도 스트릭은 살아 있는데 "연속"이 끊겼다고
// 읽히기 때문이다.
//
// 구제 대기 중이 아닐 때 안내 팝업이 뜨지 않는 것도 여기서 함께 본다 — 매번
// 뜨면 팝업 자체가 무시당한다.
//
//   flutter test test/home_streak_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/screens/home/home_screen.dart';
import 'package:booster_app/screens/main_scaffold.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late HttpServer _server;

/// 구제 대기 중인지. 테스트마다 바꿔 끼운다.
late bool _pendingRescue;

/// 대시보드 조회가 실어 보낸 `month` 쿼리. 안 실었으면 null이 들어간다.
late List<String?> _monthQueries;

/// 서버는 setUp에서 띄운다 — `testWidgets` 본문은 FakeAsync 안이라 거기서
/// [HttpServer.bind]를 부르면 서버의 idle 타이머가 가짜 시계에 잡혀 "타이머가
/// 남아 있다"로 실패한다.
void _handle(HttpRequest req, String path) {
  if (path.endsWith('/dashboard/home')) {
    // 서버는 month 를 주면 그 달의 달력을, 안 주면 이번 달을 준다.
    final month = req.uri.queryParameters['month'];
    _monthQueries.add(month);
    _sendJson(req, 200, {
      'coinBalance': 1500,
      'streak': {'current': 9, 'max': 21},
      'weeklySuccessCount': 2,
      'todayStatus': 'NOT_CHECKED',
      'calendar': {
        'year': month == null ? 2026 : int.parse(month.substring(0, 4)),
        'month': month == null ? 8 : int.parse(month.substring(4)),
        'days': <dynamic>[],
      },
    });
  } else if (path.endsWith('/users/me/location')) {
    _sendJson(req, 200, {
      'lat': 37.5,
      'lng': 127.0,
      'radiusMeters': 50,
      'placeName': '집',
    });
  } else if (path.endsWith('/users/me')) {
    _sendJson(req, 200, {
      'userId': 1,
      'email': 'a@b.c',
      'nickname': '테스터',
      'totalAttendance': 30,
      'coinBalance': 1500,
    });
  } else if (path.endsWith('/personal/weekly-goal')) {
    _sendJson(req, 200, {
      'weekStart': '2026-08-24',
      'targetDays': 3,
      'successCount': 2,
      'remainingDays': 4,
      'recoveryTickets': 0,
      'freeTickets': 0,
      'paidTickets': 0,
      'ticketPrice': 800,
      'coinBalance': 1500,
      'verificationType': 'GPS',
      'pendingRescueWeek': _pendingRescue ? '2026-08-17' : null,
      'rescueDeadline': _pendingRescue ? '2026-08-25T23:59:00' : null,
      'lateRescuePrice': 1200,
    });
  } else {
    _sendJson(req, 404, {'success': false, 'message': '요청한 정보를 찾을 수 없습니다'});
  }
}

void _sendJson(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

/// 홈을 탭 안에 넣어 띄운다. 탭을 바꿨다 돌아오는 것까지 재현하려면
/// [MainNavScope.current]가 실제로 바뀌어야 해서 상태를 들고 있는 껍데기가 필요하다.
class _TabHost extends StatefulWidget {
  const _TabHost();

  @override
  State<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends State<_TabHost> {
  int _current = 0;

  void switchTo(int index) => setState(() => _current = index);

  @override
  Widget build(BuildContext context) => MainNavScope(
        current: _current,
        select: switchTo,
        child: const HomeScreen(),
      );
}

/// 실제 통신을 일으키는 동작을 FakeAsync 밖에서 돌린다.
Future<void> _pumpHome(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      theme: BoosterTheme.light(),
      home: const _TabHost(),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

/// 다른 탭에 갔다가 홈으로 돌아온다. 홈은 그때마다 다시 읽는다.
Future<void> _reenterHomeTab(WidgetTester tester) async {
  final host = tester.state<_TabHostState>(find.byType(_TabHost));
  await tester.runAsync(() async {
    host.switchTo(1);
    await tester.pump();
    host.switchTo(0);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    _pendingRescue = false;
    _monthQueries = [];
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      await utf8.decoder.bind(req).join();
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

  group('스트릭 표기', () {
    testWidgets('연속 일수가 아니라 누적 횟수로 센다', (tester) async {
      await _pumpHome(tester);
      // 스트릭 카드는 히어로·주간목표 아래라 기본 테스트 화면(600px)에 안 들어온다.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('누적 인증'), findsOneWidget);
      expect(find.text('9'), findsWidgets);
      expect(find.text('최고 기록 21회'), findsOneWidget);

      // 하루 걸러 인증해도 끊기지 않는 값이라 '연속'으로 부르면 안 된다.
      expect(find.text('연속 인증'), findsNothing);
      expect(find.text('최고 기록 21일'), findsNothing);
    });

    testWidgets('보상 안내가 7일이 아니라 7회 기준이다', (tester) async {
      await _pumpHome(tester);
      // 보상 카드는 히어로 아래라 기본 테스트 화면(600px)에 안 들어온다.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('7회마다'), findsOneWidget);
      // 9회면 주기 안에서 2회째다. 7-2=5회 남았다.
      expect(find.text('5회 남음'), findsOneWidget);

      expect(find.text('7일 연속 인증'), findsNothing);
      expect(find.text('5일 남음'), findsNothing);
    });
  });

  group('달력 월 이동', () {
    testWidgets('보던 달은 다시 읽어도 이번 달로 튀지 않는다', (tester) async {
      await _pumpHome(tester);
      // 첫 조회는 이번 달이라 month를 싣지 않는다.
      expect(_monthQueries, [null]);

      // 달력은 목록 한참 아래라 기본 테스트 화면(600px) 밖이다.
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.chevron_left_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });
      await tester.pumpAndSettle();
      expect(_monthQueries, [null, '202607']);

      // 여기서 month를 빼고 다시 물으면 서버가 이번 달을 주고, 사용자가
      // 넘겨둔 달이 소리 없이 되감긴다.
      await _reenterHomeTab(tester);
      expect(_monthQueries, [null, '202607', '202607']);
    });
  });

  group('구제 안내 팝업', () {
    testWidgets('구제 대기 중이 아니면 뜨지 않는다', (tester) async {
      await _pumpHome(tester);

      expect(find.text('지난주 목표를 못 채웠어요'), findsNothing);
    });

    testWidgets('구제 대기 중이면 홈에 들어올 때 뜬다', (tester) async {
      // 기한이 2일뿐이라 사용자가 스스로 찾아보길 기대할 수 없다.
      _pendingRescue = true;
      await _pumpHome(tester);

      expect(find.text('지난주 목표를 못 채웠어요'), findsOneWidget);
      expect(find.text('1,200코인으로 구제하기'), findsOneWidget);
    });
  });
}
