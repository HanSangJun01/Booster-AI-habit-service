import '../core/api_client.dart';
import '../models/settlement.dart';

/// 정산 결과 — 백엔드 `SettlementController`
/// (GET /api/challenges/{challengeId}/result).
class SettlementService {
  /// 챌린지가 끝나고 정산이 돌아야 존재한다. 아직이면 서버가 404를 주므로
  /// null로 바꿔 돌려준다 — 진행 중 화면에서 그냥 "결과 없음"으로 다루면 된다.
  static Future<SettlementResult?> fetchResult(int challengeId) async {
    try {
      final data = ApiClient.asObject(await ApiClient.get('/challenges/$challengeId/result'));
      return SettlementResult.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
