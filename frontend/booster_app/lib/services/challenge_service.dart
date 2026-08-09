import '../core/api_client.dart';
import '../models/challenge.dart';
import '../models/check_in.dart';
import '../models/team.dart';

/// 챌린지 — 백엔드 `ChallengeController` / `ChallengeCheckInController`
/// (`/api/challenges`).
///
/// 백엔드 모델에서 챌린지는 최상위 엔티티다. 만든 사람이 방장이 되고, 참여는
/// [ParticipantService]로, 팀 편성은 서버가 한다.
class ChallengeService {
  /// POST /api/challenges. 챌린지 생성.
  static Future<Challenge> create(CreateChallengeRequest request) async {
    final data = ApiClient.asObject(await ApiClient.post('/challenges', body: request.toJson()));
    return Challenge.fromJson(data);
  }

  /// GET /api/challenges/{challengeId}. 상세(참가자 수·진행 일차 포함).
  static Future<Challenge> fetchDetail(int challengeId) async {
    final data = ApiClient.asObject(await ApiClient.get('/challenges/$challengeId'));
    return Challenge.fromJson(data);
  }

  /// GET /api/challenges. 공개 챌린지 검색(페이징).
  ///
  /// 서버가 Spring `Page`를 그대로 내보내므로 목록은 `content`에 들어 있다.
  static Future<List<Challenge>> search({
    String? category,
    String? keyword,
    int page = 0,
    int size = 20,
  }) async {
    final data = await ApiClient.get('/challenges', query: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      'page': page,
      'size': size,
    });
    if (data is! Map<String, dynamic>) return const [];
    final content = data['content'];
    if (content is! List) return const [];
    return content
        .whereType<Map<String, dynamic>>()
        .map(Challenge.fromJson)
        .toList();
  }

  /// GET /api/challenges/invite/{code}. 초대 코드로 챌린지 찾기.
  /// 코드가 없으면 서버가 404를 주므로 null로 바꿔 돌려준다.
  static Future<Challenge?> findByInviteCode(String code) async {
    try {
      final data = ApiClient.asObject(await ApiClient.get('/challenges/invite/$code'));
      return Challenge.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /api/challenges/{challengeId}/check-ins. 팀 챌린지 GPS 인증.
  ///
  /// 예전 스펙처럼 "체크인 생성 → 인증 제출"로 나뉘어 있지 않다. 이 한 번의
  /// 호출에서 좌표 판정까지 끝나고, 결과가 [CheckIn.status]로 돌아온다
  /// (반경을 벗어나면 서버가 에러를 준다).
  static Future<CheckIn> checkIn(
    int challengeId, {
    required double latitude,
    required double longitude,
  }) async {
    final data = ApiClient.asObject(await ApiClient.post('/challenges/$challengeId/check-ins', body: {
      'currentLat': latitude,
      'currentLng': longitude,
    }));
    return CheckIn.fromJson(data);
  }

  /// GET /api/challenges/{challengeId}/check-ins.
  /// 해당 날짜(기본값 오늘, Asia/Seoul)의 팀 전체 체크인 목록.
  static Future<List<CheckIn>> fetchCheckIns(int challengeId, {DateTime? date}) async {
    final data = await ApiClient.get('/challenges/$challengeId/check-ins', query: {
      if (date != null) 'date': _yyyymmdd(date),
    });
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(CheckIn.fromJson).toList();
  }

  /// GET /api/challenges/{challengeId}/team-detail.
  /// 내 팀 vs 상대 팀 오늘 현황. 팀 배틀 화면이 필요한 수치를 한 번에 준다.
  static Future<TeamDetail> fetchTeamDetail(int challengeId) async {
    final data = ApiClient.asObject(await ApiClient.get('/challenges/$challengeId/team-detail'));
    return TeamDetail.fromJson(data);
  }

  /// 서버 쿼리 파라미터 형식(yyyyMMdd).
  static String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}
