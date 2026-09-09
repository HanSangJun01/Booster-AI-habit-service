import '../core/api_client.dart';
import '../models/leaderboard.dart';

/// 리더보드 — 백엔드 `SocialController`
/// (GET /api/challenges/{challengeId}/leaderboards).
class LeaderboardService {
  /// type은 PERSONAL 또는 TEAM. 서버는 "TEAM"이 아닌 값은 전부 개인 리더보드로
  /// 처리한다.
  static Future<List<LeaderboardEntry>> fetch(
    int challengeId, {
    String type = 'PERSONAL',
  }) async {
    final data = await ApiClient.get(
      '/challenges/$challengeId/leaderboards',
      query: {'type': type},
    );
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(LeaderboardEntry.fromJson).toList();
  }
}
