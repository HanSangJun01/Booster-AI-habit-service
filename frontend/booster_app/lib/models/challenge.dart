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

  /// 서버가 저장한 값 그대로(`EXERCISE`·`STUDY`·`WAKE_UP`).
  ///
  /// 서버는 enum으로 제한하지 않아서 옛 챌린지에는 한글이 들어 있을 수 있다.
  /// 화면에 쓸 이름은 `ChallengeCategory.labelOf`로 옮긴다 — 이 값을 그대로
  /// 그리면 목록에 "EXERCISE"가 뜬다.
  final String category;
  final String title;
  final String? description;

  /// `VerificationType` — `GPS` / `AI` / `GPS_PHOTO_AI` 3종.
  /// `PHOTO`·`GPS_PHOTO`는 체크인이 처리하지 못해 생성 시점에 거절된다.
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
/// 서버가 받는 값이 좁다. 벗어나면 전부 400이다:
///
/// | 필드 | 허용 |
/// |---|---|
/// | `category` | `EXERCISE` / `STUDY` |
/// | `verificationType` | `GPS_PHOTO_AI` 하나 |
/// | `depositCoins` | [minDepositCoins] 이상 |
/// | `gpsRadiusMeters` | [minRadiusMeters] ~ [maxRadiusMeters] |
/// | `maxParticipants` | 10 고정 |
///
/// 정원은 고를 수 있는 값이 아니다 — 팀 편성이 "10명이 차면 5:5"라서 서버가
/// `@Min(10) @Max(10)`으로 막는다.
///
/// [title]은 더 이상 입력받지 않는다. 비워 보내면 서버가 `"운동 · 김부스터"`처럼
/// 카테고리와 방장 닉네임으로 만들어 준다.
class CreateChallengeRequest {
  /// 팀 챌린지 최소 예치금. 걸 게 없으면 져도 잃을 게 없어 판이 성립하지 않는다.
  static const int minDepositCoins = 100;

  /// 인증 반경 하한. 휴대폰 GPS 오차(10~50m)보다 좁으면 제자리에서도 인증이 실패한다.
  static const int minRadiusMeters = 10;

  /// 인증 반경 상한. 예전엔 상한이 없어 서울에 등록하고 시드니에서 인증할 수 있었다.
  static const int maxRadiusMeters = 1000;

  /// 지원하는 인증 방식. 위치만·사진만은 각각 우회가 쉬워 하나로 고정됐다.
  static const String fixedVerificationType = 'GPS_PHOTO_AI';

  final String category;

  /// 생략하면 서버가 카테고리+방장 닉네임으로 만든다.
  final String? title;
  final String? description;
  final String verificationType;
  final int durationDays;
  final int depositCoins;
  final String visibility;
  final String approvalType;
  final int maxParticipants;

  /// 방장의 인증 기준 좌표와 반경.
  ///
  /// 방장은 만드는 순간 참가자가 되므로 인증 위치가 있어야 한다. 생략하면
  /// 서버가 개인 인증 위치를 재사용하고, 그것도 없으면 400
  /// `LOCATION_REQUIRED`로 막는다. 앱은 이미 알고 있는 값을 명시해서 그
  /// 암묵적 재사용에 기대지 않는다.
  final double? gpsLat;
  final double? gpsLng;
  final int? gpsRadiusMeters;

  CreateChallengeRequest({
    required this.category,
    this.title,
    this.description,
    this.verificationType = fixedVerificationType,
    required this.durationDays,
    this.depositCoins = minDepositCoins,
    this.visibility = 'PUBLIC',
    this.approvalType = 'AUTO',
    this.maxParticipants = 10,
    this.gpsLat,
    this.gpsLng,
    this.gpsRadiusMeters,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        // 이름은 서버가 만든다. 빈 문자열을 보내면 @Size 는 통과하지만 목록에
        // 이름 없는 방으로 남으므로, 값이 있을 때만 싣는다.
        if (title != null && title!.isNotEmpty) 'title': title,
        if (description != null && description!.isNotEmpty) 'description': description,
        'verificationType': verificationType,
        'durationDays': durationDays,
        'depositCoins': depositCoins,
        'visibility': visibility,
        'approvalType': approvalType,
        'maxParticipants': maxParticipants,
        // 셋은 한 벌이다. 좌표만 있고 반경이 없으면 서버가 반경 0으로 읽어
        // 아무 데서도 인증이 안 되는 챌린지가 된다.
        if (gpsLat != null && gpsLng != null && gpsRadiusMeters != null) ...{
          'gpsLat': gpsLat,
          'gpsLng': gpsLng,
          'gpsRadiusMeters': gpsRadiusMeters,
        },
      };
}
