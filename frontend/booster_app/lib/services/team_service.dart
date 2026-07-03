import '../core/api_client.dart';
import '../core/session.dart';
import '../models/team.dart';

/// 사용자는 여러 팀에 동시에 참여할 수 있다(docs/erd/MVP_ERD.md, users-teams
/// 다대다 관계).
class TeamService {
  /// 내가 속한 모든 팀을 조회한다.
  /// GET /api/users/{userId}/teams(§6.3)는 memberCount를 포함하지 않아서,
  /// 각 팀마다 GET /api/teams/{teamId}(§6.2)를 추가로 불러 상세를 채운다.
  static Future<List<Team>> fetchMyTeams() async {
    final userId = Session.userId;
    if (userId == null) return [];

    try {
      final teams = await ApiClient.get('/users/$userId/teams') as List<dynamic>;
      final result = <Team>[];
      for (final t in teams.cast<Map<String, dynamic>>()) {
        final teamId = t['teamId'] as int;
        final detail = await ApiClient.get('/teams/$teamId') as Map<String, dynamic>;
        final team = Team.fromJson(detail);
        Session.upsertTeam(team);
        result.add(team);
      }
      return result;
    } on ApiException catch (e) {
      // statusCode == null: 서버에 아예 연결이 안 된 경우(지금처럼 백엔드가
      // 없을 때)만 캐시로 폴백한다. statusCode가 있으면 서버가 응답은 했지만
      // 에러를 준 것(인증 만료, 서버 오류 등)이라 캐시로 감추지 않고 그대로
      // 위로 던져서 실제 문제가 드러나게 한다.
      if (e.statusCode != null) rethrow;
      return Session.myTeams;
    }
  }

  /// 팀 생성 (POST /api/teams, MVP_API_SPEC §6.1). capacity/weeklyTarget/
  /// deposit/isPublic은 API에 필드가 없어 서버로 보내지 않고, 응답에 클라이언트
  /// 값을 합쳐서 돌려준다(세션 재조회 시에는 유지되지 않음).
  static Future<Team> createTeam({
    required String name,
    String? description,
    int? capacity,
    int? weeklyTarget,
    int? deposit,
    bool isPublic = true,
  }) async {
    final userId = Session.userId;
    if (userId != null) {
      try {
        final res = await ApiClient.post('/teams', body: {
          'name': name,
          if (description != null) 'description': description,
          'ownerId': userId,
        }) as Map<String, dynamic>;
        final team = Team.fromJson(res);
        final result = Team(
          teamId: team.teamId,
          name: team.name,
          description: team.description,
          ownerId: team.ownerId,
          memberCount: team.memberCount,
          capacity: capacity,
          weeklyTarget: weeklyTarget,
          deposit: deposit,
          isPublic: isPublic,
        );
        Session.upsertTeam(result);
        return result;
      } on ApiException catch (e) {
        // statusCode == null: 서버 연결 자체가 안 되는 경우만 아래 목업으로
        // 폴백한다. 서버가 응답했는데 에러라면(statusCode 있음) 그대로 던져서
        // 화면에 실제 에러 메시지가 보이게 한다 — 조용히 목업으로 감추지 않는다.
        if (e.statusCode != null) rethrow;
      }
    }
    // ── 목업 폴백: 로그인 세션이 없거나(userId == null) 위 실제 API 호출이
    // 서버 연결 실패로 끝났을 때 여기로 온다. 실제 서버에 아무것도 만들지 않고,
    // 화면에서 쓸 Team 객체만 로컬로 흉내 낸다. teamId는 여러 목업 팀이
    // 동시에 있어도 겹치지 않도록 Session.nextMockTeamId()로 발급한다.
    await Future.delayed(const Duration(milliseconds: 600));
    final mockTeamId = Session.nextMockTeamId();
    final mockTeam = Team(
      teamId: mockTeamId,
      name: name,
      description: description,
      ownerId: userId ?? 0,
      memberCount: 1,
      capacity: capacity,
      weeklyTarget: weeklyTarget,
      deposit: deposit,
      isPublic: isPublic,
    );
    Session.upsertTeam(mockTeam);
    return mockTeam;
  }

  /// 팀 참여 (POST /api/teams/{teamId}/members, MVP_API_SPEC §6.4).
  static Future<void> joinTeam(int teamId) async {
    final userId = Session.userId;
    if (userId != null) {
      try {
        await ApiClient.post('/teams/$teamId/members', body: {'userId': userId});
        Session.teamId = teamId;
        return;
      } on ApiException catch (e) {
        // statusCode == null(연결 자체 실패)일 때만 목업으로 폴백. 서버가
        // 실제 에러를 준 경우는 그대로 던진다.
        if (e.statusCode != null) rethrow;
      }
    }
    // ── 목업 폴백: 실제로 참여 요청을 보내지 않고, 참여한 것처럼 세션의
    // teamId만 채워서 화면 흐름(대기 화면 등)이 이어지게 한다.
    await Future.delayed(const Duration(milliseconds: 600));
    Session.teamId = teamId;
  }

  /// 팀원 강퇴/탈퇴 (DELETE /api/teams/{teamId}/members/{userId}, MVP_API_SPEC
  /// §6.5). teamId가 목업 팀(Session.nextMockTeamId()로 발급된 음수)이면
  /// 서버에 실존하지 않으므로 애초에 실제 호출을 시도하지 않는다.
  static Future<void> removeMember(int teamId, int userId) async {
    if (teamId > 0) {
      try {
        await ApiClient.delete('/teams/$teamId/members/$userId');
        return;
      } on ApiException catch (e) {
        // statusCode == null(연결 자체 실패)일 때만 목업으로 폴백. 서버가
        // 실제 에러를 준 경우는 그대로 던진다.
        if (e.statusCode != null) rethrow;
      }
    }
    // ── 목업 폴백: 실제로 탈퇴 요청을 보내지 않는다. 화면(TeamWaitingScreen)이
    // 로컬 멤버 목록에서 직접 지우고 인원수를 갱신한다.
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
