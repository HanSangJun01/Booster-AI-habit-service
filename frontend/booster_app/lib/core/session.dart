import '../models/challenge.dart';
import '../models/team.dart';

/// 로그인 성공 후 채워지는 현재 사용자 세션.
///
/// MVP 범위에서는 메모리에만 유지한다(앱 재시작 시 소실).
/// 재시작 후에도 로그인을 유지하려면 accessToken을 flutter_secure_storage 등에
/// 저장하고 앱 시작 시 복원하는 로직이 추가로 필요하다.
class Session {
  static int? userId;
  static String? nickname;
  static String? accessToken;

  /// 챌린지는 팀 단위로만 생성 가능(MVP_API_SPEC §7.1)하므로, 팀 생성/참여 시
  /// "가장 최근에 다룬 팀"으로 채워진다. 홈 화면의 개인 챌린지 생성 흐름
  /// (ChallengeService)이 이 값을 쓴다 — 팀 탭의 다중 팀 목록과는 별개다.
  static int? teamId;

  /// 사용자가 소속된 모든 팀의 마지막으로 알려진 상태를 캐시해둔다. docs/erd/
  /// MVP_ERD.md에 따르면 사용자는 여러 팀에 동시에 참여할 수 있다(다대다).
  /// 백엔드가 없어 TeamService.fetchMyTeams()의 실제 조회가 실패할 때, 이 값을
  /// 대신 보여줘서 "팀 만들고 뒤로가기 하면 팀이 사라져 보이는" 문제를 막는다.
  /// 실제 백엔드가 붙으면 이 캐시 없이 항상 서버 응답을 그대로 쓰면 된다.
  static List<Team> myTeams = [];

  /// 백엔드 없이 로컬로만 존재하는 팀(생성/참여 API가 실패해 목업으로 대체된
  /// 경우)에 붙이는 고유 임시 id. 여러 개를 동시에 만들 수 있어야 해서
  /// 0 같은 고정값 대신 매번 겹치지 않는 음수를 발급한다.
  static int _mockTeamSeq = 0;
  static int nextMockTeamId() => --_mockTeamSeq;

  /// 팀 정보를 최신 상태로 캐시에 반영한다(생성/참여/승인/강퇴 등 상태 변경 시).
  static void upsertTeam(Team team) {
    final idx = myTeams.indexWhere((t) => t.teamId == team.teamId);
    if (idx >= 0) {
      myTeams[idx] = team;
    } else {
      myTeams.add(team);
    }
    teamId = team.teamId;
  }

  /// 팀별로 마지막으로 알려진 진행 중 챌린지를 캐시해둔다(teamId → Challenge).
  /// 목업 챌린지(challengeId=0)는 GET으로 다시 조회할 방법이 없어서, 인증
  /// 화면 같은 곳에서 팀별 챌린지를 다시 조회할 때 이 캐시를 대신 쓴다.
  static Map<int, Challenge> teamChallenges = {};

  static void upsertChallenge(Challenge challenge) {
    teamChallenges[challenge.teamId] = challenge;
  }

  static bool get isLoggedIn => userId != null;

  static void set({required int userId, required String nickname, String? accessToken}) {
    Session.userId = userId;
    Session.nickname = nickname;
    Session.accessToken = accessToken;
  }

  static void clear() {
    userId = null;
    nickname = null;
    accessToken = null;
    teamId = null;
    myTeams = [];
    teamChallenges = {};
  }
}
