import 'json.dart';

/// AI 사진 판정 결과 — `POST .../ai-verification`의 응답.
///
/// 개인(`/personal/check-in/{id}/ai-verification`)과 팀
/// (`/verification-submissions/{id}/ai-verification`)이 같은 모양을 준다.
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

  final int currentStreak;
  final int coinBalance;
  final bool rewardGranted;

  const AiVerificationResult({
    this.date,
    required this.passed,
    this.confidenceScore,
    this.detectedLabels = const [],
    this.reason,
    required this.currentStreak,
    required this.coinBalance,
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
      currentStreak: asInt(json['currentStreak']),
      coinBalance: asInt(json['coinBalance']),
      rewardGranted: asBool(json['rewardGranted']),
    );
  }

  /// 확신도를 백분율로. 서버가 안 줬으면 null.
  int? get confidencePercent =>
      confidenceScore == null ? null : (confidenceScore! * 100).round();
}
