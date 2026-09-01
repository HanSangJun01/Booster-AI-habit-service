import 'json.dart';

/// 백엔드 `ParticipantResponse` (POST /api/challenges/{challengeId}/participants).
///
/// 챌린지 참가 신청 결과. 챌린지의 `approvalType`이 AUTO면 바로 CONFIRMED,
/// LEADER면 방장이 승인할 때까지 PENDING이다.
class Participant {
  final int id;
  final int challengeId;
  final int userId;

  /// 서버가 배정한 팀. 팀 편성 전에는 null이다.
  final int? teamId;
  final String? personalStatement;

  /// 신청자 닉네임. 서버가 필드명을 `nickname`으로 줄지 `userNickname`으로 줄지
  /// 확정돼 있지 않아 둘 다 받아본다. 없으면 null이다.
  final String? nickname;

  /// `ParticipantStatus` — PENDING | CONFIRMED | REJECTED | CANCELLED | LEFT.
  final String status;
  final DateTime? joinedAt;
  final DateTime? approvedAt;

  /// 참가 직후의 코인 잔액. **참가 신청 응답에만** 담기고 목록·승인에서는 null이다.
  ///
  /// 참가하면 예치금이 빠지는데 이 값이 없던 시절엔 앱이 화면의 코인을 갱신할 수
  /// 없어서, 참가해도 코인이 그대로 보이다가 재로그인해야 줄어드는 것처럼 보였다.
  final int? coinBalance;

  Participant({
    required this.id,
    required this.challengeId,
    required this.userId,
    this.teamId,
    this.personalStatement,
    this.nickname,
    required this.status,
    this.joinedAt,
    this.approvedAt,
    this.coinBalance,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: asInt(json['id']),
      challengeId: asInt(json['challengeId']),
      userId: asInt(json['userId']),
      teamId: asIntOrNull(json['teamId']),
      personalStatement: json['personalStatement'] as String?,
      nickname: (json['nickname'] ?? json['userNickname']) as String?,
      status: asString(json['status'], fallback: 'PENDING'),
      joinedAt: asDateTime(json['joinedAt']),
      approvedAt: asDateTime(json['approvedAt']),
      coinBalance: asIntOrNull(json['coinBalance']),
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';

  /// 목록에 쓸 이름. 서버가 닉네임을 안 주면 사용자 번호로 대신한다 —
  /// 빈칸으로 두면 방장이 누구를 승인하는지 모른 채 누르게 된다.
  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : '참가자 #$userId';
}

/// 챌린지 참가 신청 요청 (`ParticipationRequest`).
///
/// 참가할 때 **인증 기준 위치를 함께 등록**한다 — 이후 이 좌표와 반경으로
/// GPS 인증이 판정된다(공유 `GpsVerificationEvaluator`, Haversine 거리).
/// gpsLat/gpsLng/gpsRadiusMeters는 서버 필수값이다.
class ParticipationRequest {
  final String? personalStatement;
  final double gpsLat;
  final double gpsLng;
  final int gpsRadiusMeters;
  final String? gpsPlaceName;

  ParticipationRequest({
    this.personalStatement,
    required this.gpsLat,
    required this.gpsLng,
    required this.gpsRadiusMeters,
    this.gpsPlaceName,
  });

  Map<String, dynamic> toJson() => {
        if (personalStatement != null && personalStatement!.isNotEmpty)
          'personalStatement': personalStatement,
        'gpsLat': gpsLat,
        'gpsLng': gpsLng,
        'gpsRadiusMeters': gpsRadiusMeters,
        if (gpsPlaceName != null && gpsPlaceName!.isNotEmpty) 'gpsPlaceName': gpsPlaceName,
      };
}
