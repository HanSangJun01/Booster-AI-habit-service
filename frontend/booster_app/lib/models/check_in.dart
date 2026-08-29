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

  /// 사진 업로드(`POST /api/verification-submissions/{id}/ai-verification`)의
  /// 입력. **이게 없으면 AI 인증을 시작할 수 없다.**
  final int? submissionId;

  CheckIn({
    required this.id,
    this.participantId,
    this.checkInDate,
    required this.status,
    this.verifiedAt,
    this.submissionId,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      id: asInt(json['id']),
      participantId: asIntOrNull(json['participantId']),
      checkInDate: asDateOnly(json['checkInDate']),
      status: asString(json['status'], fallback: 'PENDING'),
      verifiedAt: asDateTime(json['verifiedAt']),
      submissionId: asIntOrNull(json['submissionId']),
    );
  }

  bool get isSuccess => status == 'SUCCESS' || status == 'LATE_SUCCESS';

  /// 기한을 넘겨 늦게 성공한 기록.
  bool get isLate => status == 'LATE_SUCCESS';

  /// GPS는 통과했고 사진만 남은 상태.
  bool get awaitsPhoto => status == 'PENDING';
}

/// 개인 습관 체크인 결과 — 백엔드 `personalcheckin.CheckInResponse`.
/// POST `/api/personal/check-in`.
///
/// 체크인 생성과 GPS 판정이 한 번에 끝나고, 갱신된 스트릭/코인 잔액까지
/// 함께 돌아온다. 그래서 인증 성공 후 굳이 마이페이지를 다시 조회할 필요가 없다.
class PersonalCheckInResult {
  final DateTime? date;

  /// `PersonalCheckInStatus` — SUCCESS | PENDING.
  final String status;
  final DateTime? verifiedAt;
  final int currentStreak;
  final int maxStreak;
  final int coinBalance;

  /// 이번 체크인으로 스트릭 보상(`STREAK_REWARD` +100)이 지급됐는지.
  final bool rewardGranted;

  /// 사진 업로드(`POST /api/personal/check-in/{checkInId}/ai-verification`)의
  /// 입력. **이게 없으면 AI 인증을 시작할 수 없다.**
  final int? checkInId;

  PersonalCheckInResult({
    this.date,
    required this.status,
    this.verifiedAt,
    required this.currentStreak,
    required this.maxStreak,
    required this.coinBalance,
    required this.rewardGranted,
    this.checkInId,
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
      checkInId: asIntOrNull(json['checkInId']),
    );
  }

  bool get isSuccess => status == 'SUCCESS';

  /// GPS는 끝났고 사진만 남은 상태. 인증 방식이 AI 계열일 때 나온다.
  bool get awaitsPhoto => status == 'PENDING';
}

/// 오늘의 개인 체크인 상태 — 백엔드 `TodayStatusResponse`.
/// GET `/api/personal/check-in/today`.
class TodayStatus {
  final DateTime? date;

  /// 아직 인증 전이면 서버가 비어 있는 상태값을 준다. 화면에서는 [isDone]으로만
  /// 판단하고, 원문 문자열은 표시용으로만 쓴다.
  final String status;
  final DateTime? verifiedAt;

  /// 사진 업로드에 필요한 체크인 id.
  ///
  /// ⚠️ **계약상 이 응답에는 없다**(date·status·verifiedAt뿐). 그래서 status가
  /// PENDING이어도 앱은 이어서 올릴 id를 모른다 — 앱을 껐다 켜면 사진 인증을
  /// 끝낼 방법이 없다. 서버가 나중에 실어주면 여기로 그대로 들어온다.
  final int? checkInId;

  TodayStatus({this.date, required this.status, this.verifiedAt, this.checkInId});

  factory TodayStatus.fromJson(Map<String, dynamic> json) {
    return TodayStatus(
      date: asDateOnly(json['date']),
      status: asString(json['status']),
      verifiedAt: asDateTime(json['verifiedAt']),
      checkInId: asIntOrNull(json['checkInId']),
    );
  }

  bool get isDone => status == 'SUCCESS' || verifiedAt != null;

  /// 사진 인증이 남아 있는 상태.
  ///
  /// 이걸 [isDone]으로 묶으면 안 된다 — 오늘 인증이 끝난 것처럼 보이는데 실제로는
  /// PENDING이 하루를 점유한 채 스트릭도 코인도 안 올라간다.
  bool get awaitsPhoto => status == 'PENDING';
}
