/// docs/api/MVP_API_SPEC.md §6.2 (GET /api/teams/{teamId}) 응답과 매핑되는 모델.
///
/// API는 팀 정원/예치코인/공개여부/주간 목표 필드를 전혀 지원하지 않는다
/// (§6 Teams API 참고 — 생성/조회/참여/탈퇴만 존재). 이 값들은 팀 생성 시
/// 클라이언트에서만 들고 있는 값이라, 서버에서 다시 조회한 팀은 모두 null이다.
class Team {
  final int teamId;
  final String name;
  final String? description;
  final int ownerId;
  final int memberCount;

  final int? capacity; // "3:3"→6, "4:4"→8, "5:5"→10 (client-only)
  final int? weeklyTarget; // client-only
  final int? deposit; // client-only
  final bool isPublic; // client-only, default true

  Team({
    required this.teamId,
    required this.name,
    this.description,
    required this.ownerId,
    required this.memberCount,
    this.capacity,
    this.weeklyTarget,
    this.deposit,
    this.isPublic = true,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      teamId: json['teamId'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      ownerId: json['ownerId'] as int,
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }

  bool get isFull => memberCount >= (capacity ?? 10);
}
