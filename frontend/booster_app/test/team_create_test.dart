// 챌린지 생성이 서버 제약과 어긋나지 않는지 검증한다.
//
// 백엔드가 정원을 10명으로 못 박고(`@Min(10) @Max(10)`), 방장을 생성과 동시에
// CONFIRMED 참가자로 넣으면서 인증 위치를 필수로 만들었다. 둘 다 어기면 400이라
// 챌린지를 아예 못 만든다 — 화면이 그 전에 걸러내는지 본다.
//
// 여기서는 임시 HttpServer를 띄우지 않는다. testWidgets는 본문을 fake async로
// 감싸는데, 그 안에서 HttpServer.bind를 하면 서버의 idleTimeout이 가짜 타이머가
// 되어 pumpAndSettle이 "Pending timers"로 죽는다. flutter_test 기본 오버라이드가
// 모든 요청을 즉시 400으로 돌려주므로, 위치 조회는 그대로 실패시키고 화면이
// "위치 없음" 상태에서 어떻게 행동하는지만 본다.
//
//   flutter test test/team_create_test.dart

import 'package:booster_app/core/session.dart';
import 'package:booster_app/models/challenge.dart';
import 'package:booster_app/models/challenge_category.dart';
import 'package:booster_app/screens/team/team_create_screen.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpCreate(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: BoosterTheme.light(),
    home: const TeamCreateScreen(),
  ));
  await tester.pumpAndSettle();
}

/// 목록 아래쪽 항목을 화면 안으로 끌어온다.
///
/// 폼이 ListView라 기본 테스트 화면(600px)을 넘어가는 카드는 아예 만들어지지
/// 않는다 — 스크롤하지 않으면 `find.text`가 "없다"고 답한다.
Future<void> _scrollTo(WidgetTester tester, Finder target, {double delta = 150}) async {
  await tester.scrollUntilVisible(target, delta,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// step 0(기본 정보) → step 1(공개 설정).
Future<void> _goToStep1(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '아침 러닝');
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Session.set(userId: 1, nickname: '테스터', accessToken: 'test-token');
    Session.coinBalance = 1000;
  });

  tearDown(() => Session.clear());

  group('정원', () {
    testWidgets('고를 수 없고 10명으로 고정돼 있다', (tester) async {
      await _pumpCreate(tester);
      await _scrollTo(tester, find.text('10명 고정'));

      expect(find.text('10명 고정'), findsOneWidget);
      // 정원 카드가 화면에 떠 있는 상태다 — 예전의 선택 칩이 남아 있었다면
      // 같은 카드 안이라 함께 보여야 한다. 4·6·8로 만들면 팀이 편성되지 않아
      // 아무도 인증할 수 없는 챌린지가 되고, 지금은 서버가 400으로 막는다.
      expect(find.text('4명'), findsNothing);
      expect(find.text('6명'), findsNothing);
      expect(find.text('8명'), findsNothing);
    });

    test('요청 기본값도 10이다', () {
      final json = CreateChallengeRequest(
        category: ChallengeCategory.exercise.value,
        title: '아침 러닝',
        durationDays: 14,
      ).toJson();

      expect(json['maxParticipants'], 10);
      // PHOTO·GPS_PHOTO는 체크인이 처리하지 못해 생성 시점에 서버가 거절한다.
      expect(json['verificationType'], 'GPS');
    });
  });

  group('인증 방식', () {
    // 서버는 GPS / AI / GPS_PHOTO_AI 3종만 받는다. PHOTO·GPS_PHOTO를 보내면
    // 400인데, 그대로 두면 아무도 인증 못 하는 좀비 챌린지가 되기 때문이다.
    testWidgets('3종을 고를 수 있다', (tester) async {
      await _pumpCreate(tester);
      await _scrollTo(tester, find.text('6. 인증 방법'));

      expect(find.text('위치'), findsOneWidget);
      expect(find.text('사진'), findsOneWidget);
      expect(find.text('위치 + 사진'), findsOneWidget);
    });

    testWidgets('기상에는 사진 인증을 붙일 수 없다', (tester) async {
      // 기상은 ai-service에 대응하는 어휘가 없다. 사진 인증을 붙이면 만들 수는
      // 있어도 업로드가 500으로 터져서 아무도 인증을 끝낼 수 없다.
      await _pumpCreate(tester);
      await tester.tap(find.text('기상'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('6. 인증 방법'));

      expect(find.text('위치'), findsOneWidget);
      expect(find.text('사진'), findsNothing);
      expect(find.text('위치 + 사진'), findsNothing);
    });

    testWidgets('사진을 고른 뒤 기상으로 바꾸면 위치로 되돌린다', (tester) async {
      // 고른 값이 남아 있으면 선택지에 없는 값이 그대로 서버로 나간다.
      await _pumpCreate(tester);
      await _scrollTo(tester, find.text('6. 인증 방법'));
      await tester.tap(find.text('사진'));
      await tester.pumpAndSettle();

      // 카테고리 카드는 위쪽이라 거슬러 올라가야 한다 — delta가 음수다.
      await _scrollTo(tester, find.text('기상'), delta: -150);
      await tester.tap(find.text('기상'));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('6. 인증 방법'));
      expect(find.text('사진'), findsNothing);
      expect(find.text('위치'), findsOneWidget);
    });
  });

  group('GPS 좌표', () {
    // 방장은 만드는 순간 참가자가 된다. 좌표를 생략하면 서버가 개인 인증 위치를
    // 재사용하지만, 앱이 이미 아는 값을 그 암묵적 동작에 맡길 이유가 없다.
    test('좌표와 반경을 함께 실어 보낸다', () {
      final json = CreateChallengeRequest(
        category: ChallengeCategory.exercise.value,
        title: '아침 러닝',
        durationDays: 14,
        gpsLat: 37.5,
        gpsLng: 127.0,
        gpsRadiusMeters: 50,
      ).toJson();

      expect(json['gpsLat'], 37.5);
      expect(json['gpsLng'], 127.0);
      expect(json['gpsRadiusMeters'], 50);
    });

    test('반경이 없으면 좌표도 안 보낸다', () {
      // 좌표만 가고 반경이 빠지면 서버가 반경 0으로 읽어, 어디서도 인증이 안 되는
      // 챌린지가 만들어진다. 그럴 바엔 서버 재사용 경로로 넘기는 게 낫다.
      final json = CreateChallengeRequest(
        category: ChallengeCategory.exercise.value,
        title: '아침 러닝',
        durationDays: 14,
        gpsLat: 37.5,
        gpsLng: 127.0,
      ).toJson();

      expect(json.containsKey('gpsLat'), isFalse);
      expect(json.containsKey('gpsLng'), isFalse);
      expect(json.containsKey('gpsRadiusMeters'), isFalse);
    });
  });

  group('카테고리', () {
    // 한글을 그대로 보내면 생성·참여·체크인까지 통과한 뒤 사진 업로드에서 500이
    // 난다 — ai-service가 EXERCISE/STUDY만 아는 Enum이라서다. 표시용 이름과
    // 전송값을 분리했는지가 핵심이다.
    test('서버로 나가는 값에 한글이 없다', () {
      for (final category in ChallengeCategory.values) {
        expect(category.value, matches(RegExp(r'^[A-Z_]+$')),
            reason: '${category.label}의 전송값이 영문이 아니다: ${category.value}');
      }
    });

    test('화면에 보이는 이름은 한글 그대로다', () {
      expect(ChallengeCategory.choices.map((c) => c.label).toList(),
          ['운동', '공부', '독서', '기상']);
    });

    test('독서는 STUDY로 보낸다', () {
      // ai-service 프롬프트의 STUDY 통과 기준에 활자책 독서가 들어 있다.
      expect(ChallengeCategory.reading.value, 'STUDY');
      expect(ChallengeCategory.study.value, 'STUDY');
    });

    test('기상만 AI 어휘가 아니다', () {
      // 기상 인증 사진은 운동도 공부도 아니라 대응 값이 없다. AI 계열 인증을
      // 붙이면 안 되는 유일한 카테고리다.
      expect(ChallengeCategory.wakeUp.value, isNot(anyOf('EXERCISE', 'STUDY')));
    });

    test('저장된 값을 이름으로 되돌린다', () {
      expect(ChallengeCategory.labelOf('EXERCISE'), '운동');
      // 공부와 독서가 같은 값으로 저장돼 구분이 안 된다. 한쪽으로 단정하지 않는다.
      expect(ChallengeCategory.labelOf('STUDY'), '공부·독서');
      expect(ChallengeCategory.labelOf('WAKE_UP'), '기상');
      // 이 변경 전에 만들어진 챌린지는 한글로 저장돼 있다. 억지로 매핑하면
      // 멀쩡한 이름이 빈칸이 된다.
      expect(ChallengeCategory.labelOf('운동'), '운동');
    });

    test('필터는 전송값이 겹치는 항목을 접는다', () {
      final values = ChallengeCategory.filters.map((c) => c.value).toList();
      expect(values.toSet().length, values.length, reason: '같은 결과를 주는 필터가 둘 있다');
    });

    testWidgets('선택지는 한글로 보여준다', (tester) async {
      await _pumpCreate(tester);

      for (final category in ChallengeCategory.choices) {
        expect(find.text(category.label), findsWidgets);
      }
      // 전송값이 화면에 새어 나오면 사용자가 "EXERCISE"를 고르게 된다.
      expect(find.text('EXERCISE'), findsNothing);
      expect(find.text('STUDY'), findsNothing);
    });
  });

  group('인증 위치', () {
    testWidgets('위치가 없으면 생성으로 넘어가지 않고 등록부터 안내한다', (tester) async {
      await _pumpCreate(tester);
      await _goToStep1(tester);

      await tester.tap(find.text('챌린지 만들기'));
      await tester.pump();

      expect(find.text('먼저 인증 장소를 등록해주세요'), findsOneWidget);
      // 생성으로 넘어갔다면 버튼이 '만드는 중...'으로 바뀐다. 그대로라는 건
      // 400 날 요청을 아예 안 보냈다는 뜻이다.
      expect(find.text('만드는 중...'), findsNothing);
    });

    testWidgets('방장도 참가자가 된다는 걸 미리 알린다', (tester) async {
      await _pumpCreate(tester);
      await _goToStep1(tester);

      final notice = find.text('챌린지를 만들면 나도 바로 참가자가 돼요. 예치코인도 같이 차감돼요.');
      await _scrollTo(tester, notice);
      expect(notice, findsOneWidget);
    });
  });
}
