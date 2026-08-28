import '../core/api_client.dart';
import '../core/session.dart';
import '../models/ai_verification.dart';
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

  /// GET /api/users/me/challenges. 내가 참여 중인 챌린지.
  ///
  /// 앱 재시작 후 복원용이다. 이게 없던 동안은 참여한 챌린지 id를 메모리에만
  /// 들고 있어서, 앱을 껐다 켜면 자기 챌린지를 잃어버리고 서버에서 취소·종료된
  /// 것도 알 수 없었다.
  ///
  /// 서버가 목록을 그대로 줄 수도, Spring `Page`로 감싸 줄 수도 있어서 둘 다
  /// 받아낸다 — 한쪽만 가정하면 형태가 바뀌는 날 목록이 통째로 빈다.
  static Future<List<Challenge>> fetchMine() async {
    final data = await ApiClient.get('/users/me/challenges');
    final list = data is List ? data : (data is Map ? data['content'] : null);
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(Challenge.fromJson).toList();
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

  /// POST /api/verification-submissions/{submissionId}/ai-verification.
  /// 팀 챌린지 사진 인증.
  ///
  /// 경로가 `/challenges/...` 밑이 아니다 — 제출물이 챌린지가 아니라 참가자
  /// 단위로 관리돼서 별도 컨트롤러에 있다.
  ///
  /// [aiCategory]는 `EXERCISE`/`STUDY`만 유효하다. 챌린지의 `category`를 그대로
  /// 넘기면 안 된다 — 자유 문자열이라 `WAKE_UP`이나 옛 한글이 들어 있을 수 있고,
  /// 그러면 500이 난다(`ChallengeCategory.aiValueOf` 참조).
  static Future<AiVerificationResult> verifyPhoto({
    required int submissionId,
    required String filePath,
    required List<int> bytes,
    required String aiCategory,
  }) async {
    final data = ApiClient.asObject(await ApiClient.postImage(
      '/verification-submissions/$submissionId/ai-verification',
      filePath: filePath,
      bytes: bytes,
      fields: {'category': aiCategory},
    ));
    final result = AiVerificationResult.fromJson(data);
    Session.coinBalance = result.coinBalance;
    return result;
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
