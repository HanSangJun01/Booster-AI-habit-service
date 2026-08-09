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

  /// `ParticipantStatus` — PENDING | CONFIRMED | REJECTED | CANCELLED | LEFT.
  final String status;
  final DateTime? joinedAt;
  final DateTime? approvedAt;

  Participant({
    required this.id,
    required this.challengeId,
    required this.userId,
    this.teamId,
    this.personalStatement,
    required this.status,
    this.joinedAt,
    this.approvedAt,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: asInt(json['id']),
      challengeId: asInt(json['challengeId']),
      userId: asInt(json['userId']),
      teamId: asIntOrNull(json['teamId']),
      personalStatement: json['personalStatement'] as String?,
      status: asString(json['status'], fallback: 'PENDING'),
      joinedAt: asDateTime(json['joinedAt']),
      approvedAt: asDateTime(json['approvedAt']),
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';
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
