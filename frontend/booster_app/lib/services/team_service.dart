import '../core/api_client.dart';
import '../models/team.dart';

/// 팀 — 백엔드 `TeamController` (GET /api/challenges/{challengeId}/teams).
///
/// 팀은 챌린지 안에서 서버가 편성한다. 그래서 **팀 생성/참여/탈퇴 API가 없다**:
/// - 팀에 들어가려면 챌린지에 참가한다([ParticipantService.apply])
/// - 팀에서 나오려면 챌린지 참가를 취소한다([ParticipantService.cancel])
/// - 팀 이름·정원은 사용자가 정하지 않는다
class TeamService {
  /// GET /api/challenges/{challengeId}/teams. 챌린지에 편성된 팀 목록.
  static Future<List<Team>> fetchTeams(int challengeId) async {
    final data = await ApiClient.get('/challenges/$challengeId/teams');
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(Team.fromJson).toList();
  }
}
