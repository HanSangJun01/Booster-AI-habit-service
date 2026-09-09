// P1 4건 검증.
//
//  4. 주간 목표 화면   — 서버에 있는데 볼 방법이 없던 A축 핵심
//  5. AI 사진 업로드   — 없으면 개인·팀 모두 AI 인증을 끝낼 수 없다
//  6. 참여 챌린지 복원 — 로컬 보관이라 재설치·재시작 시 유실됐다
//  7. 방장 승인 화면   — LEADER 챌린지가 시작조차 못 했다
//
// 서버는 setUp에서 띄운다 — `testWidgets` 본문은 FakeAsync 안이라 거기서
// HttpServer.bind를 부르면 idle 타이머가 가짜 시계에 잡혀 "타이머가 남아 있다"로
// 실패한다.
//
//   flutter test test/p1_flows_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:booster_app/core/api_client.dart';
import 'package:booster_app/core/session.dart';
import 'package:booster_app/models/ai_verification.dart';
import 'package:booster_app/models/challenge.dart';
import 'package:booster_app/models/challenge_category.dart';
import 'package:booster_app/models/check_in.dart';
import 'package:booster_app/screens/home/weekly_goal_screen.dart';
import 'package:booster_app/screens/team/team_approval_screen.dart';
import 'package:booster_app/screens/verify/photo_verify_sheet.dart';
import 'package:booster_app/services/challenge_service.dart';
import 'package:booster_app/services/participant_service.dart';
import 'package:booster_app/services/personal_service.dart';
import 'package:booster_app/theme/booster_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late HttpServer _server;
late void Function(HttpRequest req, String path) _handle;
late List<({String method, String path, String query, String body})> _received;

void _serveWith(void Function(HttpRequest req, String path) handle) => _handle = handle;

void _sendJson(HttpRequest req, int status, Object body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType('application', 'json');
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

void _sendNotFound(HttpRequest req) =>
    _sendJson(req, 404, {'success': false, 'message': '요청한 정보를 찾을 수 없습니다'});

Map<String, dynamic> _weeklyGoal({
  int targetDays = 3,
  int? pendingTargetDays,
  String verificationType = 'GPS',
}) {
  return {
    'weekStart': '2026-08-24',
    'targetDays': targetDays,
    'pendingTargetDays': pendingTargetDays,
    'successCount': 2,
    'remainingDays': 4,
    'recoveryTickets': 3,
    'freeTickets': 1,
    'paidTickets': 2,
    'ticketPrice': 800,
    'coinBalance': 1500,
    'verificationType': verificationType,
    'pendingRescueWeek': null,
    'rescueDeadline': null,
    'lateRescuePrice': 1200,
  };
}

Map<String, dynamic> _challengeJson({int id = 1, String category = 'EXERCISE'}) {
  return {
    'id': id,
    'category': category,
    'title': '아침 러닝 $id',
    'verificationType': 'GPS',
    'durationDays': 14,
    'depositCoins': 300,
    'visibility': 'PUBLIC',
    'approvalType': 'LEADER',
    'status': 'READY',
    'maxParticipants': 10,
    'confirmedCount': 4,
    'createdBy': 1,
  };
}

/// 실제 통신을 일으키는 동작을 FakeAsync 밖에서 돌린다.
Future<void> _withNetwork(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget screen) {
  return _withNetwork(tester, () async {
    await tester.pumpWidget(MaterialApp(theme: BoosterTheme.light(), home: screen));
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    _received = [];
    _handle = (req, _) => _sendNotFound(req);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      _received.add((
        method: req.method,
        path: req.uri.path,
        query: req.uri.query,
        body: body,
      ));
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

  // ─────────────────── P1 #6 참여 챌린지 서버 복원 ───────────────────

  group('참여 챌린지 복원', () {
    test('서버 목록으로 복원한다 — 로컬 id에 기대지 않는다', () async {
      // 이 경로는 B축이라 {success, data} 래핑이다(§A-1.2). A축처럼 raw로
      // 가정하면 목록이 통째로 빈다.
      _serveWith((req, path) {
        if (path.endsWith('/users/me/challenges')) {
          _sendJson(req, 200, {
            'success': true,
            'message': null,
            'data': [_challengeJson(id: 1), _challengeJson(id: 2)],
          });
        } else {
          _sendNotFound(req);
        }
      });

      final mine = await ChallengeService.fetchMine();

      expect(mine, hasLength(2));
      expect(_received.single.path, '/api/users/me/challenges');
    });

    test('래퍼 없이 와도 읽는다', () async {
      // 축마다 래핑이 다르고 통일은 별도 과제로 남아 있다. 한쪽만 가정하면
      // 서버가 정리되는 날 목록이 빈다.
      _serveWith((req, path) => _sendJson(req, 200, [_challengeJson(id: 3)]));

      final mine = await ChallengeService.fetchMine();

      expect(mine.single.id, 3);
    });

    test('페이지로 감싸 와도 읽는다', () async {
      _serveWith((req, path) => _sendJson(req, 200, {
            'success': true,
            'data': {
              'content': [_challengeJson(id: 7)],
              'totalElements': 1,
            },
          }));

      final mine = await ChallengeService.fetchMine();

      expect(mine, hasLength(1));
      expect(mine.single.id, 7);
    });

    test('참여가 없으면 빈 목록이다', () async {
      _serveWith((req, path) =>
          _sendJson(req, 200, {'success': true, 'data': <dynamic>[]}));
      expect(await ChallengeService.fetchMine(), isEmpty);
    });
  });

  // ─────────────────── P1 #7 방장 승인 ───────────────────

  group('방장 승인', () {
    Map<String, dynamic> pendingJson(int id, String nickname) => {
          'id': id,
          'challengeId': 1,
          'userId': id + 100,
          'nickname': nickname,
          'personalStatement': '열심히 할게요',
          'status': 'PENDING',
        };

    test('PENDING만 달라고 요청한다', () async {
      // 이 경로도 B축 래핑이다.
      _serveWith((req, path) => _sendJson(
          req, 200, {'success': true, 'data': [pendingJson(11, '민수')]}));

      await ParticipantService.fetchPending(1);

      expect(_received.single.path, '/api/challenges/1/participants');
      // status를 안 붙이면 이미 확정된 사람까지 승인 목록에 뜬다.
      expect(_received.single.query, contains('status=PENDING'));
    });

    testWidgets('대기자를 보여주고 승인하면 participantId로 보낸다', (tester) async {
      var approved = false;
      _serveWith((req, path) {
        if (path.endsWith('/approve')) {
          approved = true;
          _sendJson(req, 200, {
            'success': true,
            'data': pendingJson(11, '민수')..['status'] = 'CONFIRMED',
          });
        } else if (path.endsWith('/participants')) {
          _sendJson(req, 200, {
            'success': true,
            'data': approved ? <dynamic>[] : [pendingJson(11, '민수')],
          });
        } else {
          _sendNotFound(req);
        }
      });

      await _pump(tester,
          TeamApprovalScreen(challenge: Challenge.fromJson(_challengeJson())));

      expect(find.text('민수'), findsOneWidget);
      expect(find.text('열심히 할게요'), findsOneWidget);
      expect(find.text('대기 1명'), findsOneWidget);

      await _withNetwork(tester, () => tester.tap(find.text('승인')));

      // participantId는 목록의 data[].id다. userId(111)를 보내면 남을 승인한다.
      final approve = _received.firstWhere((r) => r.path.endsWith('/approve'));
      expect(approve.path, '/api/challenges/1/participants/11/approve');
      expect(approve.method, 'POST');
      // 승인 후 목록을 다시 읽는다 — 그 사이 정원이 찼을 수 있고 그건 서버만 안다.
      expect(find.text('승인을 기다리는 사람이 없어요'), findsOneWidget);
    });

    testWidgets('닉네임이 없어도 누구인지 알 수 있다', (tester) async {
      // 빈칸으로 두면 방장이 누구를 승인하는지 모른 채 누르게 된다.
      _serveWith((req, path) => _sendJson(req, 200, {
            'success': true,
            'data': [
              {'id': 11, 'challengeId': 1, 'userId': 42, 'status': 'PENDING'}
            ],
          }));

      await _pump(tester,
          TeamApprovalScreen(challenge: Challenge.fromJson(_challengeJson())));

      expect(find.text('참가자 #42'), findsOneWidget);
    });
  });

  // ─────────────────── P1 #4 주간 목표 화면 ───────────────────

  group('주간 목표 화면', () {
    testWidgets('이번 주 목표와 진행을 보여준다', (tester) async {
      _serveWith((req, path) => _sendJson(req, 200, _weeklyGoal(targetDays: 3)));

      await _pump(tester, const WeeklyGoalScreen());

      expect(find.text('2'), findsWidgets);
      expect(find.text(' / 3 회'), findsOneWidget);
      expect(find.text('4일 남음'), findsOneWidget);
      expect(find.text('8/24~8/30'), findsOneWidget);
    });

    testWidgets('목표 변경이 예약제라는 걸 알린다', (tester) async {
      // 즉시 반영되는 줄 알면 사용자는 저장이 안 먹은 줄 알고 계속 다시 누른다.
      _serveWith((req, path) =>
          _sendJson(req, 200, _weeklyGoal(targetDays: 3, pendingTargetDays: 5)));

      await _pump(tester, const WeeklyGoalScreen());

      expect(find.textContaining('다음 달 1일부터 주 5회로 바뀌어요'), findsOneWidget);
    });

    testWidgets('바꾼 게 없으면 저장 버튼이 눌리지 않는다', (tester) async {
      _serveWith((req, path) => _sendJson(req, 200, _weeklyGoal()));

      await _pump(tester, const WeeklyGoalScreen());
      await tester.tap(find.text('저장'));
      await tester.pump();

      // PUT이 나갔다면 목표를 안 바꾸고도 예약이 걸린다.
      expect(_received.where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('목표를 바꾸면 PUT으로 보낸다', (tester) async {
      // 조회는 예약 없는 상태(주 3회), 저장 응답은 예약이 걸린 상태로 준다.
      _serveWith((req, path) => _sendJson(
            req,
            200,
            req.method == 'PUT'
                ? _weeklyGoal(targetDays: 3, pendingTargetDays: 5)
                : _weeklyGoal(targetDays: 3),
          ));

      await _pump(tester, const WeeklyGoalScreen());
      await tester.ensureVisible(find.text('5'));
      await tester.tap(find.text('5'));
      await tester.pump();
      await _withNetwork(tester, () => tester.tap(find.text('저장')));

      final put = _received.firstWhere((r) => r.method == 'PUT');
      expect(put.path, '/api/personal/weekly-goal');
      expect(jsonDecode(put.body)['targetDays'], 5);
      // 예약제라는 걸 저장 직후에도 알려준다.
      expect(find.textContaining('다음 달 1일부터 주 5회'), findsWidgets);
    });

    test('인증 방식은 위치+사진 하나만 보낸다', () async {
      // 위치만·사진만은 각각 우회가 쉬워 GPS_PHOTO_AI 하나로 고정됐다.
      // 그 밖의 값은 서버가 400 UNSUPPORTED_VERIFICATION_TYPE 으로 거절한다.
      _serveWith((req, path) => _sendJson(req, 200, _weeklyGoal()));

      await PersonalService.updateWeeklyGoal(
          targetDays: 3, verificationType: 'GPS_PHOTO_AI');

      expect(jsonDecode(_received.single.body)['verificationType'], 'GPS_PHOTO_AI');
    });

    test('카테고리를 주면 함께 보낸다', () async {
      // 개인 목표에도 카테고리가 생겼다. 사진 인증 판정 기준이 된다.
      _serveWith((req, path) => _sendJson(req, 200, _weeklyGoal()));

      await PersonalService.updateWeeklyGoal(targetDays: 3, category: 'STUDY');

      expect(jsonDecode(_received.single.body)['category'], 'STUDY');
    });
  });

  // ─────────────────── P1 #5 AI 사진 업로드 ───────────────────

  group('사진 인증 — 카테고리', () {
    test('챌린지 값을 그대로 보내지 않는다', () {
      // ai-service는 EXERCISE/STUDY만 아는 Enum이다. 그 밖의 값을 보내면 422를
      // 주고 백엔드가 그걸 500으로 바꾼다 — 사용자 실수가 서버 장애가 된다.
      expect(ChallengeCategory.aiValueOf('EXERCISE'), 'EXERCISE');
      expect(ChallengeCategory.aiValueOf('STUDY'), 'STUDY');
      // 기상은 보낼 어휘가 없다.
      expect(ChallengeCategory.aiValueOf('WAKE_UP'), isNull);
    });

    test('옛 한글 카테고리도 받아준다', () {
      // 이 변경 전에 만들어진 챌린지가 AI 인증을 쓰고 있을 수 있다. 매핑을
      // 포기하면 그 챌린지는 영영 인증을 못 끝낸다.
      expect(ChallengeCategory.aiValueOf('운동'), 'EXERCISE');
      expect(ChallengeCategory.aiValueOf('공부'), 'STUDY');
      expect(ChallengeCategory.aiValueOf('독서'), 'STUDY');
    });

    test('사진 선택지에 기상이 없다', () {
      expect(ChallengeCategory.photoChoices, isNot(contains(ChallengeCategory.wakeUp)));
      for (final category in ChallengeCategory.photoChoices) {
        expect(category.aiValue, isNotNull);
      }
    });
  });

  group('사진 인증 — 업로드', () {
    test('multipart로 이미지와 카테고리를 보낸다', () async {
      _serveWith((req, path) => _sendJson(req, 201, {
            'date': '2026-08-29',
            'passed': true,
            'confidenceScore': 0.93,
            'detectedLabels': ['gym'],
            'currentStreak': 13,
            'coinBalance': 1600,
            'rewardGranted': true,
          }));

      final result = await PersonalService.verifyPhoto(
        checkInId: 42,
        filePath: 'photo.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
        aiCategory: 'EXERCISE',
      );

      final sent = _received.single;
      expect(sent.path, '/api/personal/check-in/42/ai-verification');
      expect(sent.body, contains('name="category"'));
      expect(sent.body, contains('EXERCISE'));
      expect(sent.body, contains('name="image"'));
      expect(result.passed, isTrue);
      expect(result.confidencePercent, 93);
      expect(Session.coinBalance, 1600);
    });

    test('팀은 제출물 경로로 올린다', () async {
      // 제출물 경로는 B축이라 래핑돼 온다(§A-1.2).
      _serveWith((req, path) => _sendJson(req, 201, {
            'success': true,
            'data': {
              'passed': true,
              'currentStreak': 5,
              'coinBalance': 900,
              'rewardGranted': false,
            },
          }));

      await ChallengeService.verifyPhoto(
        submissionId: 15,
        filePath: 'photo.png',
        bytes: Uint8List.fromList([1]),
        aiCategory: 'STUDY',
      );

      // 챌린지 밑이 아니다 — 제출물은 참가자 단위라 별도 컨트롤러에 있다.
      expect(_received.single.path, '/api/verification-submissions/15/ai-verification');
    });

    test('보낼 수 없는 형식은 올리기 전에 막는다', () async {
      // 서버는 415를 주지만, 그건 파일을 다 올려보낸 뒤에 오는 답이다.
      await expectLater(
        PersonalService.verifyPhoto(
          checkInId: 1,
          filePath: 'photo.gif',
          bytes: Uint8List.fromList([1]),
          aiCategory: 'EXERCISE',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('JPG·PNG·WEBP'))),
      );
      expect(_received, isEmpty);
    });

    test('10MB를 넘으면 올리기 전에 막는다', () async {
      await expectLater(
        PersonalService.verifyPhoto(
          checkInId: 1,
          filePath: 'photo.jpg',
          bytes: Uint8List(ApiClient.maxUploadBytes + 1),
          aiCategory: 'EXERCISE',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('10MB'))),
      );
      expect(_received, isEmpty);
    });
  });

  group('사진 인증 — 바텀시트', () {
    /// 사진 고르기를 갈아끼운다. image_picker는 테스트에서 동작하지 않는다.
    ImagePickFn pickFake({bool cancelled = false}) {
      return (source) async => cancelled
          ? null
          : PickedImage(path: 'photo.jpg', bytes: Uint8List.fromList([1, 2, 3]));
    }

    Future<AiVerificationResult?> pumpSheet(
      WidgetTester tester, {
      required ImagePickFn pick,
      String? fixedAiCategory,
      required Future<AiVerificationResult> Function(String, Uint8List, String) upload,
    }) async {
      AiVerificationResult? result;
      await tester.pumpWidget(MaterialApp(
        theme: BoosterTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await showPhotoVerifySheet(
                  context,
                  pick: pick,
                  request: PhotoVerifyRequest(
                    subtitle: '오늘의 습관을 찍어서 올려주세요.',
                    fixedAiCategory: fixedAiCategory,
                    upload: upload,
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('개인은 카테고리를 고르게 한다', (tester) async {
      // 개인 트랙에는 카테고리를 저장하는 컬럼이 아예 없어서 매번 물어야 한다.
      await pumpSheet(tester,
          pick: pickFake(),
          fixedAiCategory: null,
          upload: (_, __, ___) async => throw StateError('안 불려야 한다'));

      expect(find.text('무엇을 인증하나요?'), findsOneWidget);
      for (final category in ChallengeCategory.photoChoices) {
        expect(find.text(category.label), findsOneWidget);
      }
      expect(find.text('기상'), findsNothing);
    });

    testWidgets('팀은 카테고리를 안 묻는다', (tester) async {
      await pumpSheet(tester,
          pick: pickFake(),
          fixedAiCategory: 'EXERCISE',
          upload: (_, __, ___) async => throw StateError('안 불려야 한다'));

      expect(find.text('무엇을 인증하나요?'), findsNothing);
    });

    testWidgets('고른 카테고리가 그대로 업로드에 실린다', (tester) async {
      String? sent;
      await pumpSheet(
        tester,
        pick: pickFake(),
        fixedAiCategory: null,
        upload: (path, bytes, category) async {
          sent = category;
          return const AiVerificationResult(
            passed: true,
            currentStreak: 13,
            coinBalance: 1600,
            rewardGranted: true,
          );
        },
      );

      await tester.tap(find.text('독서'));
      await tester.pump();
      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      // 독서는 STUDY로 나간다 — '독서'를 그대로 보내면 500이다.
      expect(sent, 'STUDY');
      expect(find.text('인증했어요'), findsOneWidget);
      expect(find.text('13회'), findsOneWidget);
      expect(find.text('+100 코인'), findsOneWidget);
    });

    testWidgets('사진 고르기를 그만두면 실패로 처리하지 않는다', (tester) async {
      var uploaded = false;
      await pumpSheet(
        tester,
        pick: pickFake(cancelled: true),
        fixedAiCategory: 'EXERCISE',
        upload: (_, __, ___) async {
          uploaded = true;
          return const AiVerificationResult(
            passed: true,
            currentStreak: 1,
            coinBalance: 0,
            rewardGranted: false,
          );
        },
      );

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      expect(uploaded, isFalse);
      // 고르는 화면 그대로다.
      expect(find.text('사진으로 인증하기'), findsOneWidget);
      expect(find.text('올리지 못했어요'), findsNothing);
    });

    testWidgets('거절돼도 오늘이 끝난 게 아니라고 알린다', (tester) async {
      // 거절되면 서버가 체크인 레코드를 지운다 — 그날 재시도할 수 있다.
      await pumpSheet(
        tester,
        pick: pickFake(),
        fixedAiCategory: 'EXERCISE',
        upload: (_, __, ___) async => const AiVerificationResult(
          passed: false,
          reason: '운동하는 모습이 보이지 않아요',
          currentStreak: 12,
          coinBalance: 1500,
          rewardGranted: false,
        ),
      );

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      expect(find.text('사진을 확인하지 못했어요'), findsOneWidget);
      expect(find.text('운동하는 모습이 보이지 않아요'), findsOneWidget);
      expect(find.textContaining('오늘 다시 시도할 수 있어요'), findsOneWidget);
      expect(find.text('다시 찍기'), findsOneWidget);
    });

    testWidgets('업로드가 실패해도 인증이 남아 있다고 알린다', (tester) async {
      // 502가 나도 체크인은 PENDING으로 남는다. "실패했다"로만 말하면 사용자가
      // 오늘을 포기한다.
      await pumpSheet(
        tester,
        pick: pickFake(),
        fixedAiCategory: 'EXERCISE',
        upload: (_, __, ___) async => throw ApiException('AI 서비스에 연결할 수 없습니다',
            statusCode: 502),
      );

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      expect(find.text('올리지 못했어요'), findsOneWidget);
      expect(find.text('AI 서비스에 연결할 수 없습니다'), findsOneWidget);
      expect(find.textContaining('인증은 아직 남아 있어요'), findsOneWidget);
    });
  });

  group('사진이 남은 상태', () {
    test('PENDING을 완료로 세지 않는다', () {
      // 완료로 묶으면 오늘 인증이 끝난 것처럼 보이는데, 실제로는 스트릭도 코인도
      // 안 오른 채 PENDING이 하루를 점유한다.
      final pending = TodayStatus.fromJson({'date': '2026-08-29', 'status': 'PENDING'});
      expect(pending.awaitsPhoto, isTrue);
      expect(pending.isDone, isFalse);
    });

    test('체크인 응답에서 업로드 입력값을 꺼낸다', () {
      final personal = PersonalCheckInResult.fromJson({
        'date': '2026-08-29',
        'status': 'PENDING',
        'currentStreak': 12,
        'maxStreak': 30,
        'coinBalance': 1500,
        'rewardGranted': false,
        'checkInId': 43,
      });
      expect(personal.awaitsPhoto, isTrue);
      expect(personal.checkInId, 43);

      final team = CheckIn.fromJson({
        'id': 1,
        'checkInDate': '2026-08-29',
        'status': 'PENDING',
        'submissionId': 15,
      });
      expect(team.awaitsPhoto, isTrue);
      expect(team.submissionId, 15);
      expect(team.isSuccess, isFalse);
    });
  });
}
