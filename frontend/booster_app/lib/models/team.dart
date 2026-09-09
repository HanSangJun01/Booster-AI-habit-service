import 'json.dart';

/// 백엔드 `TeamResponse` (GET /api/challenges/{challengeId}/teams).
///
/// 팀은 챌린지 안에서 편성되는 하위 개념이라, 사용자가 직접 만들거나 이름을
/// 정하지 않는다. 팀 생성/참여/탈퇴 API는 백엔드에 없다 — 참여는 챌린지 참가
/// (`POST /api/challenges/{id}/participants`)로 이뤄지고 팀 배정은 서버가 한다.
class Team {
  final int id;
  final int challengeId;
  final String name;

  /// 팀 참여율(0.0~1.0). 서버가 BigDecimal로 내보내서 JSON에서는 정수로도
  /// 실수로도 올 수 있다.
  final double participationRate;

  /// `TeamResult` — WIN | LOSE | DRAW. 정산 전에는 null.
  final String? result;

  /// 편성 시점 인원. 중도 이탈해도 줄지 않는다(정산 기준).
  final int initialMemberCount;

  Team({
    required this.id,
    required this.challengeId,
    required this.name,
    required this.participationRate,
    this.result,
    required this.initialMemberCount,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: asInt(json['id']),
      challengeId: asInt(json['challengeId']),
      name: asString(json['name']),
      participationRate: asDouble(json['participationRate']),
      result: json['result'] as String?,
      initialMemberCount: asInt(json['initialMemberCount']),
    );
  }

  /// 참여율을 백분율 정수로. 화면 표시용.
  int get participationPercent => (participationRate * 100).round();
}

/// 팀 대결 현황 — 백엔드 `TeamDetailResponse`
/// (GET /api/challenges/{challengeId}/team-detail).
///
/// 내 팀과 상대 팀을 함께 내려주므로, 팀 배틀 화면이 필요한 수치를 이 한
/// 번의 호출로 모두 채울 수 있다.
class TeamDetail {
  final TeamSide? myTeam;
  final TeamSide? opponentTeam;

  /// 챌린지 시작 기준 며칠째인지. 시작 전이면 null.
  final int? challengeDay;
  final int totalDays;
  final DateTime? today;

  TeamDetail({
    this.myTeam,
    this.opponentTeam,
    this.challengeDay,
    required this.totalDays,
    this.today,
  });

  factory TeamDetail.fromJson(Map<String, dynamic> json) {
    return TeamDetail(
      myTeam: json['myTeam'] is Map<String, dynamic>
          ? TeamSide.fromJson(json['myTeam'] as Map<String, dynamic>)
          : null,
      opponentTeam: json['opponentTeam'] is Map<String, dynamic>
          ? TeamSide.fromJson(json['opponentTeam'] as Map<String, dynamic>)
          : null,
      challengeDay: asIntOrNull(json['challengeDay']),
      totalDays: asInt(json['totalDays']),
      today: asDateOnly(json['today']),
    );
  }
}

/// `TeamDetailResponse.TeamInfo` — 대결 한쪽 팀의 오늘 현황.
class TeamSide {
  final int teamId;
  final String teamName;
  final double participationRate;
  final int todayCheckedInCount;
  final int totalMemberCount;
  final List<TeamMemberStatus> members;

  TeamSide({
    required this.teamId,
    required this.teamName,
    required this.participationRate,
    required this.todayCheckedInCount,
    required this.totalMemberCount,
    required this.members,
  });

  factory TeamSide.fromJson(Map<String, dynamic> json) {
    return TeamSide(
      teamId: asInt(json['teamId']),
      teamName: asString(json['teamName']),
      participationRate: asDouble(json['participationRate']),
      todayCheckedInCount: asInt(json['todayCheckedInCount']),
      totalMemberCount: asInt(json['totalMemberCount']),
      members: asObjectList(json['members']).map(TeamMemberStatus.fromJson).toList(),
    );
  }

  int get participationPercent => (participationRate * 100).round();
}

/// `TeamMemberCheckInStatus` — 팀원 한 명의 오늘 인증 여부.
class TeamMemberStatus {
  final int? userId;
  final int? participantId;
  final bool checkedIn;

  /// `CheckInStatus`. 오늘 기록이 없으면 null.
  final String? status;

  TeamMemberStatus({
    this.userId,
    this.participantId,
    required this.checkedIn,
    this.status,
  });

  factory TeamMemberStatus.fromJson(Map<String, dynamic> json) {
    return TeamMemberStatus(
      userId: asIntOrNull(json['userId']),
      participantId: asIntOrNull(json['participantId']),
      checkedIn: asBool(json['checkedIn']),
      status: json['status'] as String?,
    );
  }
}
