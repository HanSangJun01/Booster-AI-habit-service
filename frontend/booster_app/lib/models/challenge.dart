/// docs/api/MVP_API_SPEC.md §7.2 (GET /api/challenges/{challengeId}) 응답과 매핑되는 모델.
class Challenge {
  final int challengeId;
  final int teamId;
  final String title;
  final String? description;
  final String startDate;
  final String endDate;
  final String status; // READY | ACTIVE | ENDED | CANCELLED
  final String verificationType;
  final String? deadlineTime;
  final bool recoveryEnabled;

  /// 주간 목표 인증 횟수(챌린지 생성 화면의 "주 몇 회"). API 스펙에 대응
  /// 필드가 없어 서버에 저장되지 않는 클라이언트 전용 값 — 생성 직후에만
  /// 채워지고, 서버에서 다시 조회한 챌린지는 null이다.
  final int? weeklyTarget;

  Challenge({
    required this.challengeId,
    required this.teamId,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.verificationType,
    this.deadlineTime,
    required this.recoveryEnabled,
    this.weeklyTarget,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      challengeId: json['challengeId'] as int,
      teamId: json['teamId'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      status: json['status'] as String,
      verificationType: json['verificationType'] as String,
      deadlineTime: json['deadlineTime'] as String?,
      recoveryEnabled: json['recoveryEnabled'] as bool? ?? false,
    );
  }
}
