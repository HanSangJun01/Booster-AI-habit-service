import 'json.dart';

/// 챌린지(팀) 체크인 — 백엔드 `challengecheckin.CheckInResponse`.
/// POST/GET `/api/challenges/{challengeId}/check-ins`.
///
/// 개인 습관 체크인(`PersonalCheckInResult`)과는 응답 모양이 완전히 다르다.
/// 이쪽은 참가자(participantId) 단위 기록이다.
class CheckIn {
  final int id;
  final int? participantId;
  final DateTime? checkInDate;

  /// `CheckInStatus` — SUCCESS | FAILED | LATE_SUCCESS | PENDING.
  final String status;
  final DateTime? verifiedAt;

  CheckIn({
    required this.id,
    this.participantId,
    this.checkInDate,
    required this.status,
    this.verifiedAt,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      id: asInt(json['id']),
      participantId: asIntOrNull(json['participantId']),
      checkInDate: asDateOnly(json['checkInDate']),
      status: asString(json['status'], fallback: 'PENDING'),
      verifiedAt: asDateTime(json['verifiedAt']),
    );
  }

  bool get isSuccess => status == 'SUCCESS' || status == 'LATE_SUCCESS';

  /// 기한을 넘겨 늦게 성공한 기록.
  bool get isLate => status == 'LATE_SUCCESS';
}

/// 개인 습관 체크인 결과 — 백엔드 `personalcheckin.CheckInResponse`.
/// POST `/api/personal/check-in`.
///
/// 체크인 생성과 GPS 판정이 한 번에 끝나고, 갱신된 스트릭/코인 잔액까지
/// 함께 돌아온다. 그래서 인증 성공 후 굳이 마이페이지를 다시 조회할 필요가 없다.
class PersonalCheckInResult {
  final DateTime? date;

  /// `PersonalCheckInStatus` — SUCCESS | RECOVERY_PENDING | FAILED.
  final String status;
  final DateTime? verifiedAt;
  final int currentStreak;
  final int maxStreak;
  final int coinBalance;

  /// 이번 체크인으로 스트릭 보상(`STREAK_REWARD` +100)이 지급됐는지.
  final bool rewardGranted;

  PersonalCheckInResult({
    this.date,
    required this.status,
    this.verifiedAt,
    required this.currentStreak,
    required this.maxStreak,
    required this.coinBalance,
    required this.rewardGranted,
  });

  factory PersonalCheckInResult.fromJson(Map<String, dynamic> json) {
    return PersonalCheckInResult(
      date: asDateOnly(json['date']),
      status: asString(json['status'], fallback: 'SUCCESS'),
      verifiedAt: asDateTime(json['verifiedAt']),
      currentStreak: asInt(json['currentStreak']),
      maxStreak: asInt(json['maxStreak']),
      coinBalance: asInt(json['coinBalance']),
      rewardGranted: asBool(json['rewardGranted']),
    );
  }

  bool get isSuccess => status == 'SUCCESS';

  /// 미인증으로 복귀 미션이 열린 상태.
  bool get needsRecovery => status == 'RECOVERY_PENDING';
}

/// 오늘의 개인 체크인 상태 — 백엔드 `TodayStatusResponse`.
/// GET `/api/personal/check-in/today`.
class TodayStatus {
  final DateTime? date;

  /// 아직 인증 전이면 서버가 비어 있는 상태값을 준다. 화면에서는 [isDone]으로만
  /// 판단하고, 원문 문자열은 표시용으로만 쓴다.
  final String status;
  final DateTime? verifiedAt;

  TodayStatus({this.date, required this.status, this.verifiedAt});

  factory TodayStatus.fromJson(Map<String, dynamic> json) {
    return TodayStatus(
      date: asDateOnly(json['date']),
      status: asString(json['status']),
      verifiedAt: asDateTime(json['verifiedAt']),
    );
  }

  bool get isDone => status == 'SUCCESS' || verifiedAt != null;
  bool get needsRecovery => status == 'RECOVERY_PENDING';
}
