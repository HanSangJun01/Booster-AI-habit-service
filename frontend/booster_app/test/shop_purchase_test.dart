// 상점 — 구제권 구매 검증.
//
// 확인하려는 건 세 가지다.
//  1. 구매가 **서버 도메인 API**로 나간다는 것 — `POST /api/personal/recovery-tickets`.
//     예전의 `POST /api/users/me/coins`(범용 코인 증감)는 서버에 없고 앞으로도
//     안 생긴다. 그 경로로 돌아가면 잔액이 앱 마음대로 움직이게 된다.
//  2. 보유 수량·가격·잔액의 주인이 **서버**라는 것 — 앱은 기기에 아무것도
//     남기지 않고, 가격을 하드코딩하지도 않는다.
//  3. '사용' 버튼이 없다는 것 — 소모는 주간 채점 때 서버가 한다.
//
// 서버는 각 테스트가 직접 띄운다 — 빈 포트를 받으므로 진짜 백엔드(:8080)와
// 부딪히지 않는다.
//
//   flutter test

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/models/shop_item.dart';
import 'package:booster_app/screens/main_scaffold.dart';
import 'package:booster_app/screens/shop/shop_screen.dart';
import 'package:booster_app/services/shop_service.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ticket = ShopCatalog.recoveryTicket;

/// 서버가 받아본 요청들. 어디로 무엇을 보냈는지 확인하는 데 쓴다.
late List<({String method, String path, String body})> _received;

/// `GET /api/personal/weekly-goal` 응답 본문.
Map<String, dynamic> _weeklyGoal({
  int freeTickets = 0,
  int paidTickets = 0,
  int ticketPrice = 800,
  int coinBalance = 1500,
}) {
  return {
    'weekStart': '2026-08-24',
    'targetDays': 3,
    'pendingTargetDays': null,
    'successCount': 2,
    'remainingDays': 4,
    'recoveryTickets': freeTickets + paidTickets,
    'freeTickets': freeTickets,
    'paidTickets': paidTickets,
    'ticketPrice': ticketPrice,
    'coinBalance': coinBalance,
    'verificationType': 'GPS',
    'lastWeekResult': 'ACHIEVED',
    'pendingRescueWeek': null,
    'rescueDeadline': null,
    'lateRescuePrice': 1200,
  };
}

late HttpServer _server;

/// 지금 걸려 있는 응답 규칙. [_serveWith]로 테스트마다 갈아끼운다.
late void Function(HttpRequest req, String path) _handle;

/// 경로별 응답 규칙을 건다.
///
/// 상점 화면이 주간 목표를 읽고 구매는 다른 경로로 보내기 때문에, 하나의
/// 핸들러로 뭉뚱그리면 "어디로 보냈는지"를 확인할 수 없다.
///
/// 서버 자체는 setUp에서 띄운다 — `testWidgets`의 본문은 FakeAsync 안이라
/// 거기서 [HttpServer.bind]를 부르면 서버의 idle 타이머가 가짜 시계에 잡혀
/// "테스트가 끝났는데 타이머가 남아 있다"로 실패한다.
void _serveWith(void Function(HttpRequest req, String path) handle) =>
    _handle = handle;

void _sendJson(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

void _sendNotFound(HttpRequest req) =>
    _sendJson(req, 404, {'success': false, 'message': '요청한 정보를 찾을 수 없습니다'});

/// 주간 목표 조회만 응답하고 나머지는 404로 두는 기본 규칙.
void _serveGoal(Map<String, dynamic> goal) {
  _serveWith((req, path) {
    if (path.endsWith('/personal/weekly-goal')) {
      _sendJson(req, 200, goal);
    } else {
      _sendNotFound(req);
    }
  });
}

/// 실제 통신을 일으키는 동작을 FakeAsync 밖에서 돌린다.
///
/// `testWidgets` 본문은 가짜 시계 위에서 돌아가서, 그 안에서 시작한 소켓 I/O는
/// 영영 끝나지 않는다. 풀어주지 않으면 화면이 로딩 상태로 굳어서 정작 확인하려는
/// 내용이 하나도 안 그려진다.
Future<void> _withNetwork(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    // 임시 서버가 응답하고 화면이 그걸 반영할 틈.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test는 기본적으로 모든 HTTP를 가로채 400으로 돌려준다.
    HttpOverrides.global = null;
  });

  setUp(() async {
    _received = [];
    _handle = (req, _) => _sendNotFound(req);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      _received.add((method: req.method, path: req.uri.path, body: body));
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

  group('구매', () {
    test('구제권 도메인 API로 나간다 — 코인 증감 경로를 쓰지 않는다', () async {
      _serveWith((req, path) => _sendJson(req, 201, {
            'recoveryTickets': 1,
            'price': 800,
            'coinBalance': 700,
          }));

      await ShopService.purchase(_ticket);

      expect(_received, hasLength(1));
      expect(_received.single.method, 'POST');
      expect(_received.single.path, '/api/personal/recovery-tickets');
      // 서버에 없고 만들지도 않을 경로. 여기로 돌아가면 잔액을 앱이 조작하게 된다.
      expect(_received.single.path, isNot(contains('/users/me/coins')));
    });

    test('요청 본문이 없다 — 무엇을 사는지는 경로가 말해준다', () async {
      _serveWith((req, path) => _sendJson(req, 201, {
            'recoveryTickets': 1,
            'price': 800,
            'coinBalance': 700,
          }));

      await ShopService.purchase(_ticket);

      expect(_received.single.body, isEmpty);
    });

    test('잔액은 서버가 준 값을 따른다', () async {
      _serveWith((req, path) => _sendJson(req, 201, {
            'recoveryTickets': 3,
            'price': 800,
            'coinBalance': 377,
          }));

      final result = await ShopService.purchase(_ticket);

      expect(result.recoveryTickets, 3);
      expect(result.price, 800);
      expect(result.coinBalance, 377);
      // 앱이 1500-800=700으로 계산하지 않고 서버 값을 쓴다.
      expect(Session.coinBalance, 377);
    });

    test('잔액이 모자라면 서버가 막고 코인은 그대로다', () async {
      // 판정의 최종 주체는 서버다. 앱은 버튼을 흐리게 하는 정도만 한다.
      _serveWith((req, path) => _sendJson(req, 400, {
            'success': false,
            'message': '코인이 부족합니다',
            'errorCode': 'INSUFFICIENT_COIN',
          }));

      await expectLater(
        ShopService.purchase(_ticket),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('코인이 부족'))),
      );
      expect(Session.coinBalance, 1500);
    });

    test('기프티콘은 살 수 없다 — 요청 자체를 보내지 않는다', () async {
      _serveWith((req, path) => _sendJson(req, 201, {}));

      await expectLater(
        ShopService.purchase(ShopCatalog.gifticons.first),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('판매하지 않는'))),
      );
      expect(_received, isEmpty);
    });
  });

  group('현황 조회', () {
    test('위치 미등록이면 에러가 아니라 없음으로 온다', () async {
      // 아직 시작 전인 사용자다. 이걸 에러로 올리면 상점을 열 때마다 빨간
      // 토스트가 뜬다.
      _serveWith((req, path) => _sendJson(req, 400, {
            'success': false,
            'message': '인증 위치가 등록되지 않았습니다',
            'errorCode': 'LOCATION_NOT_REGISTERED',
          }));

      expect(await ShopService.fetchStatus(), isNull);
    });

    test('무료분과 구매분을 나눠 읽는다', () async {
      _serveGoal(_weeklyGoal(freeTickets: 1, paidTickets: 2));

      final goal = await ShopService.fetchStatus();

      expect(goal!.freeTickets, 1);
      expect(goal.paidTickets, 2);
      expect(goal.recoveryTickets, 3);
      expect(goal.ticketPrice, 800);
      expect(goal.lateRescuePrice, 1200);
    });
  });

  group('상점 화면', () {
    /// 상점은 탭 하나라 [MainNavScope] 없이는 그려지지 않는다(하단 내비가
    /// 현재 탭을 묻는다). 실제 배치와 같게 감싸준다.
    Future<void> pumpShop(WidgetTester tester) {
      return _withNetwork(tester, () async {
        await tester.pumpWidget(MaterialApp(
          theme: BoosterTheme.light(),
          home: MainNavScope(
            current: 3,
            select: (_) {},
            child: const ShopScreen(),
          ),
        ));
      });
    }

    testWidgets('가격을 서버 값으로 보여준다 — 앱에 박아두지 않는다', (tester) async {
      // 서버가 950으로 바꿔도 화면이 따라가야 한다. 앱이 100을 들고 있으면
      // "표시는 100인데 결제는 950"이 된다.
      _serveGoal(_weeklyGoal(ticketPrice: 950));
      await pumpShop(tester);

      expect(find.text('950'), findsOneWidget);
      expect(find.text('코인 부족'), findsNothing);
      // '구매'는 보유함의 구매분 라벨에도 쓰여서 버튼만 세지 않는다.
      expect(find.text('구매'), findsWidgets);
    });

    testWidgets('보유분을 무료/구매로 나눠 보여준다', (tester) async {
      // 소멸 규칙이 달라서 합쳐 놓으면 월말에 하나가 사라진 걸 설명할 수 없다.
      _serveGoal(_weeklyGoal(freeTickets: 1, paidTickets: 2));
      await pumpShop(tester);

      expect(find.text('내 구제권'), findsOneWidget);
      expect(find.text('3개 보유'), findsOneWidget);
      expect(find.text('무료'), findsOneWidget);
      expect(find.text('1개'), findsOneWidget);
      expect(find.text('이번 달 말 소멸'), findsOneWidget);
      expect(find.text('2개'), findsOneWidget);
      expect(find.text('소멸 없음'), findsOneWidget);
    });

    testWidgets('보유해도 사용 버튼은 없다', (tester) async {
      // 쓰는 시점을 사용자가 고르지 않는다 — 주간 채점 때 서버가 알아서
      // 소모한다. 버튼을 두면 앱이 하지도 않는 일을 약속하게 된다.
      _serveGoal(_weeklyGoal(freeTickets: 1, paidTickets: 2));
      await pumpShop(tester);

      expect(find.text('사용'), findsNothing);
      expect(find.text('사용하기'), findsNothing);
    });

    testWidgets('잔액이 모자라면 구매 버튼이 코인 부족으로 바뀐다', (tester) async {
      _serveGoal(_weeklyGoal(ticketPrice: 800, coinBalance: 799));
      await pumpShop(tester);

      expect(find.text('코인 부족'), findsOneWidget);
    });

    testWidgets('현황을 못 읽어도 화면은 열린다', (tester) async {
      // 위치 미등록 사용자. 구제권을 살 수는 없지만 기프티콘 구경과 새로고침은
      // 되어야 한다 — 여기서 로딩에 묶이면 빠져나갈 길이 없다.
      _serveWith((req, path) => _sendJson(req, 400, {
            'success': false,
            'message': '인증 위치가 등록되지 않았습니다',
            'errorCode': 'LOCATION_NOT_REGISTERED',
          }));
      await pumpShop(tester);

      expect(find.text('내 구제권'), findsOneWidget);
      expect(find.text('인증 장소를 등록하면 구제권을 확인할 수 있어요'), findsOneWidget);
      expect(find.text('구매 불가'), findsOneWidget);
      expect(find.text('기프티콘'), findsOneWidget);
    });

    /// 기프티콘 구역은 목록 아래쪽이라 기본 테스트 화면(600px)에는 안 들어온다.
    /// ListView가 화면 밖 자식을 만들어두지 않아서 스크롤해야 finder에 잡힌다.
    Future<void> scrollToGifticons(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    testWidgets('기프티콘은 외관만 — 전부 준비 중으로 잠겨 있다', (tester) async {
      _serveGoal(_weeklyGoal());
      await pumpShop(tester);
      await scrollToGifticons(tester);

      for (final gifticon in ShopCatalog.gifticons) {
        expect(find.text(gifticon.name), findsOneWidget);
      }
      // 카드마다 하나씩. 섹션 제목 옆 태그는 스크롤에 밀려 화면 밖이다.
      expect(find.text('준비 중'), findsNWidgets(ShopCatalog.gifticons.length));
    });

    testWidgets('기프티콘을 눌러도 구매로 가지 않는다', (tester) async {
      _serveGoal(_weeklyGoal());
      await pumpShop(tester);
      await scrollToGifticons(tester);

      await tester.tap(find.text(ShopCatalog.gifticons.first.name));
      await tester.pump();

      expect(find.text('기프티콘 교환은 준비 중이에요'), findsOneWidget);
      // 구매 경로로 나간 요청이 없어야 한다.
      expect(
        _received.where((r) => r.path.contains('recovery-tickets')),
        isEmpty,
      );
    });
  });
}
