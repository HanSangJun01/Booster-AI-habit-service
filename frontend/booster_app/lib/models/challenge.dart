import 'json.dart';

/// 백엔드 `ChallengeResponse` / `ChallengeDetailResponse`.
///
/// 백엔드 모델에서는 **챌린지가 최상위**다. 사용자가 챌린지를 만들고, 다른
/// 사용자가 참여를 신청하면 그 안에서 팀이 편성된다
/// (`GET /api/challenges/{challengeId}/teams`). 예전 스펙의 "팀이 챌린지를
/// 소유하는" 구조와는 방향이 반대다.
///
/// [confirmedCount]·[currentDay]는 상세 조회(GET /api/challenges/{id})에만
/// 있고 목록/생성 응답에는 없어서 null일 수 있다.
class Challenge {
  final int id;

  /// 자유 문자열(예: "운동", "공부"). 서버가 enum으로 제한하지 않는다.
  final String category;
  final String title;
  final String? description;

  /// `VerificationType` — MVP는 GPS만 쓴다.
  final String verificationType;
  final int durationDays;

  /// 참가 시 차감되는 예치 코인.
  final int depositCoins;

  /// `ChallengeVisibility` — PUBLIC | PRIVATE.
  final String visibility;

  /// `ApprovalType` — AUTO(자동 승인) | LEADER(방장 승인).
  final String approvalType;

  /// `ChallengeStatus` — READY | ACTIVE | ENDED | CANCELLED.
  final String status;

  /// 초대 코드. 코드로 챌린지를 찾을 때 쓴다
  /// (GET /api/challenges/invite/{code}).
  final String? inviteCode;
  final int maxParticipants;

  /// 승인 완료(CONFIRMED)된 참가자 수. 상세 조회에만 포함된다.
  final int? confirmedCount;

  /// 시작일 기준 며칠째인지(1부터). 시작 전이면 null.
  final int? currentDay;

  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? createdBy;
  final DateTime? createdAt;

  Challenge({
    required this.id,
    required this.category,
    required this.title,
    this.description,
    required this.verificationType,
    required this.durationDays,
    required this.depositCoins,
    required this.visibility,
    required this.approvalType,
    required this.status,
    this.inviteCode,
    required this.maxParticipants,
    this.confirmedCount,
    this.currentDay,
    this.startedAt,
    this.endedAt,
    this.createdBy,
    this.createdAt,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      id: asInt(json['id']),
      category: asString(json['category']),
      title: asString(json['title']),
      description: json['description'] as String?,
      verificationType: asString(json['verificationType'], fallback: 'GPS'),
      durationDays: asInt(json['durationDays']),
      depositCoins: asInt(json['depositCoins']),
      visibility: asString(json['visibility'], fallback: 'PUBLIC'),
      approvalType: asString(json['approvalType'], fallback: 'AUTO'),
      status: asString(json['status'], fallback: 'READY'),
      inviteCode: json['inviteCode'] as String?,
      maxParticipants: asInt(json['maxParticipants']),
      confirmedCount: asIntOrNull(json['confirmedCount']),
      currentDay: asIntOrNull(json['currentDay']),
      startedAt: asDateTime(json['startedAt']),
      endedAt: asDateTime(json['endedAt']),
      createdBy: asIntOrNull(json['createdBy']),
      createdAt: asDateTime(json['createdAt']),
    );
  }

  bool get isActive => status == 'ACTIVE';
  bool get isReady => status == 'READY';
  bool get isEnded => status == 'ENDED' || status == 'CANCELLED';
  bool get isPrivate => visibility == 'PRIVATE';
  bool get needsLeaderApproval => approvalType == 'LEADER';

  /// 정원이 찼는지. confirmedCount가 있는 상세 조회 결과에서만 판정된다.
  bool get isFull => confirmedCount != null && confirmedCount! >= maxParticipants;
}

/// 챌린지 생성 요청 (`CreateChallengeRequest`, POST /api/challenges).
///
/// 서버 검증: durationDays >= 1, depositCoins >= 0, maxParticipants 2~10,
/// title 200자 이내.
class CreateChallengeRequest {
  final String category;
  final String title;
  final String? description;
  final String verificationType;
  final int durationDays;
  final int depositCoins;
  final String visibility;
  final String approvalType;
  final int maxParticipants;

  CreateChallengeRequest({
    required this.category,
    required this.title,
    this.description,
    this.verificationType = 'GPS',
    required this.durationDays,
    this.depositCoins = 0,
    this.visibility = 'PUBLIC',
    this.approvalType = 'AUTO',
    this.maxParticipants = 10,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'title': title,
        if (description != null && description!.isNotEmpty) 'description': description,
        'verificationType': verificationType,
        'durationDays': durationDays,
        'depositCoins': depositCoins,
        'visibility': visibility,
        'approvalType': approvalType,
        'maxParticipants': maxParticipants,
      };
}
