import 'json.dart';

/// 백엔드 `SettlementResultResponse` (GET /api/challenges/{challengeId}/result).
///
/// 챌린지가 끝나고 정산이 완료돼야 존재한다. 정산 전에 조회하면 서버가
/// 404(NOT_FOUND)를 준다.
class SettlementResult {
  final int challengeId;

  /// `SettlementStatus` — PENDING | COMPLETED | FAILED.
  final String status;
  final bool draw;
  final int? winnerTeamId;
  final int? loserTeamId;

  /// 승패에 걸린 예치금 총액.
  final int totalPool;

  /// 승자 1인당 지급액(내림 처리).
  final int perWinnerPayout;
  final DateTime? computedAt;

  SettlementResult({
    required this.challengeId,
    required this.status,
    required this.draw,
    this.winnerTeamId,
    this.loserTeamId,
    required this.totalPool,
    required this.perWinnerPayout,
    this.computedAt,
  });

  factory SettlementResult.fromJson(Map<String, dynamic> json) {
    return SettlementResult(
      challengeId: asInt(json['challengeId']),
      status: asString(json['status'], fallback: 'PENDING'),
      draw: asBool(json['draw']),
      winnerTeamId: asIntOrNull(json['winnerTeamId']),
      loserTeamId: asIntOrNull(json['loserTeamId']),
      totalPool: asInt(json['totalPool']),
      perWinnerPayout: asInt(json['perWinnerPayout']),
      computedAt: asDateTime(json['computedAt']),
    );
  }

  bool get isCompleted => status == 'COMPLETED';
}
