import 'json.dart';

/// 백엔드 `RecoveryStatusResponse` (GET /api/personal/recovery/status).
///
/// 개인 체크인을 놓치면 복귀 미션이 열리고, 데드라인 안에 GPS 인증을 다시
/// 하면 만회된다. 미션이 없으면 [hasPendingMission]이 false다.
class RecoveryStatus {
  final bool hasPendingMission;
  final int? recoveryMissionId;

  /// 놓친 날짜.
  final DateTime? missedDate;

  /// 이 시각을 넘기면 미션이 실패 처리된다.
  final DateTime? deadlineAt;

  RecoveryStatus({
    required this.hasPendingMission,
    this.recoveryMissionId,
    this.missedDate,
    this.deadlineAt,
  });

  static const none = RecoveryStatus._none();
  const RecoveryStatus._none()
      : hasPendingMission = false,
        recoveryMissionId = null,
        missedDate = null,
        deadlineAt = null;

  factory RecoveryStatus.fromJson(Map<String, dynamic> json) {
    return RecoveryStatus(
      hasPendingMission: asBool(json['hasPendingMission']),
      recoveryMissionId: asIntOrNull(json['recoveryMissionId']),
      missedDate: asDateOnly(json['missedDate']),
      deadlineAt: asDateTime(json['deadlineAt']),
    );
  }

  /// 데드라인까지 남은 시간. 미션이 없거나 이미 지났으면 null.
  Duration? get remaining {
    final deadline = deadlineAt;
    if (!hasPendingMission || deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? null : left;
  }
}

/// 백엔드 `RecoveryResultResponse` (POST /api/personal/recovery).
class RecoveryResult {
  final int? recoveryMissionId;

  /// `RecoveryStatus` enum — PENDING | COMPLETED | FAILED.
  final String status;
  final DateTime? completedAt;
  final int currentStreak;
  final int coinBalance;

  /// 이번 복귀로 차감된 코인. 성공은 `RECOVERY_SUCCESS`(-50),
  /// 실패는 `RECOVERY_FAILURE`(-100)로 기록된다.
  final int chargedAmount;

  RecoveryResult({
    this.recoveryMissionId,
    required this.status,
    this.completedAt,
    required this.currentStreak,
    required this.coinBalance,
    required this.chargedAmount,
  });

  factory RecoveryResult.fromJson(Map<String, dynamic> json) {
    return RecoveryResult(
      recoveryMissionId: asIntOrNull(json['recoveryMissionId']),
      status: asString(json['status'], fallback: 'PENDING'),
      completedAt: asDateTime(json['completedAt']),
      currentStreak: asInt(json['currentStreak']),
      coinBalance: asInt(json['coinBalance']),
      chargedAmount: asInt(json['chargedAmount']),
    );
  }

  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
}
