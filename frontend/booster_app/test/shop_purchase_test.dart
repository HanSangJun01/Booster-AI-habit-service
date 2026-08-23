// 상점 구매/사용 검증.
//
// 확인하려는 건 두 가지다.
//  1. 서버로 나가는 게 **가격뿐**이라는 것 — 어떤 물건인지는 보내지 않는다.
//  2. 코인과 보유 수량이 항상 같이 움직인다는 것 — 한쪽만 반영되고 끝나는
//     경우가 없어야 한다(코인만 빠지고 물건이 안 들어오는 게 최악이다).
//
// 코인 증감 엔드포인트는 아직 백엔드에 없다. 없을 때(404) 로컬 폴백으로
// 이어가는 경로와, 생겼을 때 서버 잔액을 따르는 경로를 모두 태운다.
//
// 서버는 각 테스트가 직접 띄운다 — 빈 포트를 받으므로 진짜 백엔드(:8080)와
// 부딪히지 않는다.
//
//   flutter test

import 'dart:convert';
import 'dart:io';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/inventory.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/models/shop_item.dart';
import 'package:booster_app/screens/main_scaffold.dart';
import 'package:booster_app/screens/shop/shop_screen.dart';
import 'package:booster_app/services/shop_service.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ticket = ShopCatalog.recoveryTicket;

/// 서버가 받아본 요청 바디들. "가격만 보낸다"를 확인하는 데 쓴다.
late List<Map<String, dynamic>> _received;

/// [handle]로 응답하는 임시 서버를 띄우고 [ApiClient]가 그리로 향하게 한다.
Future<void> _serveWith(void Function(HttpRequest req, Map<String, dynamic> body) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final raw = await utf8.decoder.bind(req).join();
    final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    _received.add(body);
    handle(req, body);
  });
  ApiClient.overrideBaseUrl('http://${server.address.host}:${server.port}/api');

  addTearDown(() async {
    ApiClient.overrideBaseUrl(null);
    await server.close(force: true);
  });
}

void _sendJson(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test는 기본적으로 모든 HTTP를 가로채 400으로 돌려준다.
    HttpOverrides.global = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _received = [];
    Session.set(userId: 1, nickname: '테스터', accessToken: 'test-token');
    Session.coinBalance = 500;
    Inventory.clear();
    await Inventory.load();
  });

  tearDown(() {
    Inventory.clear();
    Session.clear();
  });

  group('구매', () {
    test('엔드포인트가 없으면(404) 로컬 잔액으로 이어간다', () async {
      // 지금 백엔드에 코인 증감 API가 없다. 그때도 상점이 멈추지 않아야 한다.
      await _serveWith((req, _) => _sendJson(req, 404, {
            'success': false,
            'message': '요청한 정보를 찾을 수 없습니다',
          }));

      final balance = await ShopService.purchase(_ticket);

      expect(balance, 500 - _ticket.price);
      expect(Session.coinBalance, 500 - _ticket.price);
      expect(Inventory.countOf(_ticket.id), 1);
    });

    test('서버가 잔액을 주면 그 값을 따른다', () async {
      // 서버가 진짜 계산 주체가 되면 앱 계산이 아니라 서버 값이 기준이다.
      await _serveWith((req, _) => _sendJson(req, 200, {'coinBalance': 377}));

      final balance = await ShopService.purchase(_ticket);

      expect(balance, 377);
      expect(Session.coinBalance, 377);
      expect(Inventory.countOf(_ticket.id), 1);
    });

    test('서버로 나가는 건 가격뿐 — 어떤 물건인지는 보내지 않는다', () async {
      await _serveWith((req, _) => _sendJson(req, 200, {'coinBalance': 400}));

      await ShopService.purchase(_ticket);

      expect(_received, hasLength(1));
      expect(_received.single, {'amount': -_ticket.price});
      // 상품 id/이름이 섞여 나가면 서버가 카탈로그를 아는 셈이 된다.
      expect(jsonEncode(_received.single), isNot(contains(_ticket.id)));
      expect(jsonEncode(_received.single), isNot(contains(_ticket.name)));
    });

    test('코인이 모자라면 요청 자체를 보내지 않는다', () async {
      await _serveWith((req, _) => _sendJson(req, 200, {'coinBalance': 0}));
      Session.coinBalance = _ticket.price - 1;

      await expectLater(
        ShopService.purchase(_ticket),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('코인이 부족'))),
      );
      expect(_received, isEmpty);
      expect(Inventory.countOf(_ticket.id), 0);
      expect(Session.coinBalance, _ticket.price - 1);
    });

    test('코인 차감이 실패하면 보유분도 없던 일이 된다', () async {
      // 404가 아닌 진짜 실패(5xx). 물건만 남고 코인은 그대로면 공짜로 산 게 된다.
      await _serveWith((req, _) => _sendJson(req, 500, {
            'success': false,
            'message': '서버 오류',
          }));

      await expectLater(ShopService.purchase(_ticket), throwsA(isA<ApiException>()));

      expect(Inventory.countOf(_ticket.id), 0);
      expect(Session.coinBalance, 500);
    });

    test('기프티콘은 살 수 없다', () async {
      await _serveWith((req, _) => _sendJson(req, 200, {'coinBalance': 0}));

      await expectLater(
        ShopService.purchase(ShopCatalog.gifticons.first),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('판매하지 않는'))),
      );
      expect(_received, isEmpty);
    });
  });

  group('사용', () {
    test('보유분이 줄고 코인이 돌아온다', () async {
      await _serveWith((req, body) {
        final amount = body['amount'] as int;
        _sendJson(req, 200, {'coinBalance': 500 + amount});
      });
      await Inventory.add(_ticket.id);

      final balance = await ShopService.use(_ticket);

      expect(balance, 500 + _ticket.refundAmount);
      expect(Inventory.countOf(_ticket.id), 0);
      expect(_received.single, {'amount': _ticket.refundAmount});
    });

    test('보유분이 없으면 코인도 움직이지 않는다', () async {
      await _serveWith((req, _) => _sendJson(req, 200, {'coinBalance': 9999}));

      await expectLater(
        ShopService.use(_ticket),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('보유한'))),
      );
      expect(_received, isEmpty);
      expect(Session.coinBalance, 500);
    });

    test('환급이 실패하면 보유분이 되돌아온다', () async {
      await _serveWith((req, _) => _sendJson(req, 500, {
            'success': false,
            'message': '서버 오류',
          }));
      await Inventory.add(_ticket.id);

      await expectLater(ShopService.use(_ticket), throwsA(isA<ApiException>()));

      // 썼는데 코인은 못 받고 물건까지 사라지면 그냥 없어진 것이다.
      expect(Inventory.countOf(_ticket.id), 1);
      expect(Session.coinBalance, 500);
    });
  });

  group('보유함 저장', () {
    test('계정이 다르면 보유분이 섞이지 않는다', () async {
      // 저장소는 계정이 아니라 기기 단위다. 키에 userId가 빠지면 한 기기에서
      // 계정을 바꿔 로그인했을 때 앞사람 보유분이 그대로 보인다.
      await Inventory.add(_ticket.id);
      expect(Inventory.countOf(_ticket.id), 1);

      Session.userId = 2;
      await Inventory.load();
      expect(Inventory.countOf(_ticket.id), 0);

      Session.userId = 1;
      await Inventory.load();
      expect(Inventory.countOf(_ticket.id), 1);
    });

    test('로그아웃하면 메모리에서 비워진다', () async {
      await Inventory.add(_ticket.id);
      Session.onClear = Inventory.clear;
      addTearDown(() => Session.onClear = null);

      Session.clear();

      expect(Inventory.countOf(_ticket.id), 0);
    });
  });

  group('상점 화면', () {
    /// 상점은 탭 하나라 [MainNavScope] 없이는 그려지지 않는다(하단 내비가
    /// 현재 탭을 묻는다). 실제 배치와 같게 감싸준다.
    Future<void> pumpShop(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: BoosterTheme.light(),
        home: MainNavScope(
          current: 3,
          select: (_) {},
          child: const ShopScreen(),
        ),
      ));
      // 잔액 조회는 테스트 환경에서 실패한다(HttpOverrides가 400을 준다).
      // 그래도 화면이 열려야 한다는 것 자체가 확인 대상이다.
      await tester.pumpAndSettle();
    }

    testWidgets('보유분이 없으면 보유함이 비어 있다고 알려준다', (tester) async {
      await pumpShop(tester);

      expect(find.text('내 보유함'), findsOneWidget);
      expect(find.text('비어 있음'), findsOneWidget);
      expect(find.text('아직 없어요. 아래에서 구매할 수 있어요'), findsOneWidget);
    });

    testWidgets('구제권은 가격과 함께 구매할 수 있게 나온다', (tester) async {
      await pumpShop(tester);

      expect(find.text(_ticket.name), findsWidgets);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('구매'), findsOneWidget);
      expect(find.text('코인 부족'), findsNothing);
    });

    testWidgets('잔액이 모자라면 구매 버튼이 코인 부족으로 바뀐다', (tester) async {
      Session.coinBalance = _ticket.price - 1;
      await pumpShop(tester);

      expect(find.text('코인 부족'), findsOneWidget);
      expect(find.text('구매'), findsNothing);
    });

    testWidgets('보유분이 있으면 사용 안내가 함께 나온다', (tester) async {
      await Inventory.add(_ticket.id);
      await pumpShop(tester);

      expect(find.text('1개 보유'), findsOneWidget);
      expect(find.text('복귀 미션으로 코인이 빠졌을 때 사용하세요'), findsOneWidget);
      expect(find.text('사용'), findsOneWidget);
    });

    testWidgets('기프티콘은 외관만 — 전부 준비 중으로 잠겨 있다', (tester) async {
      await pumpShop(tester);

      expect(find.text('기프티콘'), findsOneWidget);
      for (final gifticon in ShopCatalog.gifticons) {
        expect(find.text(gifticon.name), findsOneWidget);
      }
      // 섹션 제목 옆 하나 + 카드마다 하나.
      expect(find.text('준비 중'), findsNWidgets(ShopCatalog.gifticons.length + 1));
    });

    testWidgets('기프티콘을 눌러도 구매로 가지 않는다', (tester) async {
      await pumpShop(tester);

      // 기프티콘 구역은 목록 아래쪽이라 기본 테스트 화면(600px)에는 안 들어온다.
      // scrollUntilVisible은 여기서 안 통한다 — ListView(children:)가 자식을
      // 전부 만들어두는 탓에 finder가 처음부터 찾아버려서 스크롤을 건너뛴다.
      final card = find.text(ShopCatalog.gifticons.first.name);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();

      await tester.tap(card);
      await tester.pump();

      expect(find.text('기프티콘 교환은 준비 중이에요'), findsOneWidget);
      expect(Session.coinBalance, 500);
      expect(Inventory.countOf(ShopCatalog.gifticons.first.id), 0);
    });
  });
}
