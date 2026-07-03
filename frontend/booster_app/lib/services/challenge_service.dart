import '../core/api_client.dart';
import '../core/session.dart';
import '../models/challenge.dart';
import '../models/check_in.dart';
import 'team_service.dart';

/// 홈 화면 진입 지점. 현재 로그인한 사용자가 참여 중인 팀들 중 진행 중(ACTIVE)
/// 챌린지가 있는 첫 팀의 챌린지를 조회한다. 없으면 null → 홈 화면은
/// "챌린지 생성 전" 빈 상태를 보여준다.
///
/// 사용자당 팀이 여러 개일 수 있어서(§6.3), 팀을 순서대로 확인하며 챌린지가
/// 있는 팀을 찾는다. MVP 홈 화면은 그 챌린지 하나만 보여준다 — 팀 선택
/// UI는 범위 밖.
class ChallengeService {
  static Future<Challenge?> fetchActiveChallenge() async {
    final userId = Session.userId;
    if (userId == null) return null;

    // TeamService.fetchMyTeams()는 서버 연결 실패 시 Session.myTeams 캐시로
    // 폴백해준다 — 여기서 직접 /users/{id}/teams를 부르면 그 안전장치를
    // 잃어버리므로 재사용한다.
    final teams = await TeamService.fetchMyTeams();
    for (final team in teams) {
      final challenge = await fetchActiveChallengeForTeam(team.teamId);
      if (challenge != null) return challenge;
    }
    // 팀 목록에서 못 찾았으면(팀이 아예 없거나, 있어도 매칭 안 됨) 팀 없이
    // 만들어진 개인 챌린지 캐시도 확인한다 — createChallenge()가 생성 당시
    // teamId가 없었으면 0으로 캐시해둔다. 나중에 팀이 생겨도 이 챌린지의
    // teamId는 그대로 0이라 위 팀 목록 순회에서는 못 찾는다.
    return Session.teamChallenges[0];
  }

  /// 특정 팀의 진행 중(ACTIVE) 챌린지를 조회한다. 인증 화면의 팀별 카드처럼
  /// "이 팀"의 챌린지가 필요한 곳에서 쓴다 — fetchActiveChallenge()는 항상
  /// 첫 번째 팀만 보므로 여러 팀을 다룰 땐 이 함수를 팀마다 호출한다.
  static Future<Challenge?> fetchActiveChallengeForTeam(int teamId) async {
    if (teamId <= 0) {
      // 목업 팀(Session.nextMockTeamId())은 서버에 없어 GET으로 조회가
      // 불가능하다 — createChallenge()가 만들 때 캐시해둔 값을 대신 쓴다.
      return Session.teamChallenges[teamId];
    }

    try {
      final challenges = await ApiClient.get('/teams/$teamId/challenges') as List<dynamic>;
      final activeSummary = challenges.cast<Map<String, dynamic>>().where(
            (c) => c['status'] == 'ACTIVE',
          );
      if (activeSummary.isEmpty) return null;

      final challengeId = activeSummary.first['challengeId'] as int;
      final detail = await ApiClient.get('/challenges/$challengeId') as Map<String, dynamic>;
      final challenge = Challenge.fromJson(detail);
      Session.upsertChallenge(challenge);
      return challenge;
    } on ApiException catch (e) {
      if (e.statusCode != null) rethrow;
      return Session.teamChallenges[teamId];
    }
  }

  /// 챌린지 생성 (POST /api/teams/{teamId}/challenges, MVP_API_SPEC §7.1).
  /// 생성된 챌린지를 반환한다 — 홈 화면은 이 값을 바로 써서 별도 재조회 없이
  /// 즉시 "챌린지 있음" 상태로 전환한다.
  ///
  /// API 요청 바디는 title/startDate/endDate/verificationType/deadlineTime/
  /// recoveryEnabled만 지원한다. 생성 화면의 "주 몇 회", "인증 위치"는
  /// 현재 스펙에 대응 필드가 없어 서버로 전송하지 않는다 — 백엔드에 필드가
  /// 추가되면 이 함수의 body에 반영한다.
  ///
  /// 응답(§7.1)에는 startDate/endDate/deadlineTime/recoveryEnabled가 포함되지
  /// 않으므로, 요청 시 보낸 값을 그대로 합쳐서 완전한 Challenge를 만든다.
  /// 참고: 생성 직후 status는 스펙상 ACTIVE가 아니라 READY다(§14.1) — 실제
  /// 백엔드가 붙으면 "생성 직후 바로 진행 중으로 볼지" 여부를 백엔드와
  /// 맞춰야 한다.
  static Future<Challenge> createChallenge({
    required String title,
    required String startDate,
    required String endDate,
    String deadlineTime = '23:00',
    bool recoveryEnabled = true,
    int? weeklyTarget,
  }) async {
    final teamId = Session.teamId;
    if (teamId != null && teamId > 0) {
      try {
        final res = await ApiClient.post('/teams/$teamId/challenges', body: {
          'title': title,
          'startDate': startDate,
          'endDate': endDate,
          'verificationType': 'GPS',
          'deadlineTime': deadlineTime,
          'recoveryEnabled': recoveryEnabled,
        }) as Map<String, dynamic>;
        final result = Challenge(
          challengeId: res['challengeId'] as int,
          teamId: res['teamId'] as int,
          title: res['title'] as String,
          startDate: startDate,
          endDate: endDate,
          status: res['status'] as String,
          verificationType: res['verificationType'] as String,
          deadlineTime: deadlineTime,
          recoveryEnabled: recoveryEnabled,
          // weeklyTarget은 API가 저장/반환하지 않으므로, 방금 보낸 요청의 값을
          // 그대로 화면에 되돌려준다(서버 재조회 시에는 유지되지 않음).
          weeklyTarget: weeklyTarget,
        );
        Session.upsertChallenge(result);
        return result;
      } on ApiException catch (e) {
        // statusCode == null(연결 자체 실패)일 때만 아래 목업으로 폴백한다.
        // 서버가 실제 에러를 준 경우는 그대로 던져서 화면에 드러낸다.
        if (e.statusCode != null) rethrow;
      }
    }
    // ── 목업 폴백: teamId가 없거나(팀이 아예 없음) 목업 팀(음수)이거나,
    // 위 실제 API 호출이 서버 연결 실패로 끝났을 때 여기로 온다. teamId는
    // 실제 요청에 쓰려던 값을 그대로 유지해야, 인증 화면 등에서
    // fetchActiveChallengeForTeam(teamId)로 다시 찾을 수 있다(Session.
    // teamChallenges 캐시 참고). challengeId는 서버 미할당 표식인 0을 쓴다.
    await Future.delayed(const Duration(milliseconds: 600));
    final result = Challenge(
      challengeId: 0,
      teamId: teamId ?? 0,
      title: title,
      startDate: startDate,
      endDate: endDate,
      status: 'ACTIVE',
      verificationType: 'GPS',
      deadlineTime: deadlineTime,
      recoveryEnabled: recoveryEnabled,
      weeklyTarget: weeklyTarget,
    );
    Session.upsertChallenge(result);
    return result;
  }

  /// 챌린지 체크인(인증) 기록 조회 (GET /api/challenges/{challengeId}/check-ins,
  /// MVP_API_SPEC §8.2). 연속 인증일수/이번 주 성공일/누적 인증/달력은 모두
  /// 이 목록에서 계산한다.
  static Future<List<CheckIn>> fetchCheckIns(int challengeId) async {
    if (challengeId == 0) {
      // createChallenge()의 mock 경로(teamId 미배정)로 만들어진 챌린지 —
      // 서버에 실존하지 않으므로 조회할 체크인이 없다.
      return [];
    }
    final list = await ApiClient.get('/challenges/$challengeId/check-ins') as List<dynamic>;
    return list.cast<Map<String, dynamic>>().map(CheckIn.fromJson).toList();
  }

  /// 오늘 체크인 생성 (POST /api/challenges/{challengeId}/check-ins, §8.1).
  /// 생성만으로는 최종 합격 여부가 안 정해진다 — 바로 이어서
  /// submitGpsVerification()으로 위치 인증을 제출해야 finalPassed가 나온다.
  static Future<CheckIn> createCheckIn(int challengeId) async {
    final today = _todayString();
    if (challengeId == 0) {
      // 목업 챌린지(§createChallenge 주석 참고) — 서버에 실존하지 않는다.
      await Future.delayed(const Duration(milliseconds: 400));
      return CheckIn(checkInId: 0, checkInDate: today, status: 'PENDING');
    }
    final res = await ApiClient.post('/challenges/$challengeId/check-ins', body: {
      'userId': Session.userId,
      'checkInDate': today,
      'status': 'PENDING',
    }) as Map<String, dynamic>;
    return CheckIn.fromJson(res);
  }

  /// GPS 위치 인증 제출 (POST /api/check-ins/{checkInId}/verification-submissions,
  /// §9.1). 최종 합격 여부(finalPassed)를 반환한다.
  ///
  /// TODO: 실제 기기 GPS 좌표를 보내야 한다 — 아직 geolocator 같은 위치 패키지가
  /// 없어서, 화면에 표시된 "서울 서초구 반포한강공원" 좌표를 그대로 보낸다.
  static Future<bool> submitGpsVerification(
    int checkInId, {
    double latitude = 37.5093,
    double longitude = 126.9976,
  }) async {
    if (checkInId == 0) {
      await Future.delayed(const Duration(milliseconds: 400));
      return true;
    }
    final res = await ApiClient.post('/check-ins/$checkInId/verification-submissions', body: {
      'latitude': latitude,
      'longitude': longitude,
    }) as Map<String, dynamic>;
    return res['finalPassed'] as bool? ?? false;
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
