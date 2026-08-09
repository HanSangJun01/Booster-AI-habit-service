import 'json.dart';

/// 백엔드 `LeaderboardEntry`
/// (GET /api/challenges/{challengeId}/leaderboards?type=PERSONAL|TEAM).
///
/// 개인/팀 리더보드가 같은 항목 타입을 공유한다. PERSONAL이면 [userId]와
/// [name](닉네임)이, TEAM이면 [teamId]와 [name](팀명)이 채워진다.
class LeaderboardEntry {
  final int rank;
  final int? userId;
  final int? teamId;
  final String name;

  /// 성공한 인증 횟수.
  final int checkInCount;

  /// 참여율(0.0~1.0). 서버가 BigDecimal로 내보낸다.
  final double participationRate;

  LeaderboardEntry({
    required this.rank,
    this.userId,
    this.teamId,
    required this.name,
    required this.checkInCount,
    required this.participationRate,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: asInt(json['rank']),
      userId: asIntOrNull(json['userId']),
      teamId: asIntOrNull(json['teamId']),
      name: asString(json['name'], fallback: '이름 없음'),
      checkInCount: asInt(json['checkInCount']),
      participationRate: asDouble(json['participationRate']),
    );
  }

  int get participationPercent => (participationRate * 100).round();
}
