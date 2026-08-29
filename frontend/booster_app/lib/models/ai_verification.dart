import 'json.dart';

/// AI 사진 판정 결과 — `POST .../ai-verification`의 응답.
///
/// 개인(`/personal/check-in/{id}/ai-verification`)과 팀
/// (`/verification-submissions/{id}/ai-verification`)은 **모양이 다르다.**
///
/// 공통으로 오는 건 판정부([passed]·[confidenceScore]·[detectedLabels]·[reason])
/// 뿐이다. [currentStreak]·[coinBalance]·[rewardGranted]는 개인 트랙에만 있다 —
/// 팀은 체크인마다 코인을 주지 않고, 챌린지가 끝날 때 예치금을 정산해 분배한다
/// (`SettlementService`). 그래서 팀 응답에는 스트릭도 코인도 애초에 없다.
///
/// 없는 값을 0으로 읽으면 "인증은 됐는데 코인이 0"처럼 보이므로 null로 둔다.
/// 화면은 null이면 그 줄을 그리지 않는다.
///
/// ## 거절돼도 그날은 끝이 아니다
/// [passed]가 false면 서버가 개인 체크인 레코드를 **삭제한다**. PENDING이 하루를
/// 점유해 재시도가 막히는 걸 막으려는 것이라, 사용자에게는 "오늘 실패"가 아니라
/// "다시 찍어서 올리면 된다"로 안내해야 한다.
class AiVerificationResult {
  final DateTime? date;

  /// 판정 통과 여부.
  final bool passed;

  /// 0~1 확신도. 서버가 안 주면 null이다.
  final double? confidenceScore;

  /// 사진에서 읽어낸 것들(예: `["gym", "dumbbell"]`).
  final List<String> detectedLabels;

  /// 거절 사유. 통과했으면 null이다. 사용자에게 그대로 보여줄 수 있는 문장이다.
  final String? reason;

  /// 개인 트랙에서만 온다. 팀 인증이면 null이다.
  final int? currentStreak;

  /// 개인 트랙에서만 온다. 팀 인증이면 null이므로 세션 잔액을 덮어쓰면 안 된다.
  final int? coinBalance;

  /// 개인 트랙의 스트릭 보상 지급 여부. 팀 응답엔 없어서 false다.
  final bool rewardGranted;

  const AiVerificationResult({
    this.date,
    required this.passed,
    this.confidenceScore,
    this.detectedLabels = const [],
    this.reason,
    this.currentStreak,
    this.coinBalance,
    required this.rewardGranted,
  });

  factory AiVerificationResult.fromJson(Map<String, dynamic> json) {
    final labels = json['detectedLabels'];
    return AiVerificationResult(
      date: asDateOnly(json['date']),
      passed: asBool(json['passed']),
      confidenceScore:
          json['confidenceScore'] == null ? null : asDouble(json['confidenceScore']),
      detectedLabels:
          labels is List ? labels.whereType<String>().toList() : const <String>[],
      reason: json['reason'] as String?,
      currentStreak: asIntOrNull(json['currentStreak']),
      coinBalance: asIntOrNull(json['coinBalance']),
      rewardGranted: asBool(json['rewardGranted']),
    );
  }

  /// 확신도를 백분율로. 서버가 안 줬으면 null.
  int? get confidencePercent =>
      confidenceScore == null ? null : (confidenceScore! * 100).round();
}
