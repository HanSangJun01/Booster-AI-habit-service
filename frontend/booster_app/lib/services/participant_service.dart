import '../core/api_client.dart';
import '../core/session.dart';
import '../models/participant.dart';

/// 챌린지 참가 — 백엔드 `ParticipantController`
/// (`/api/challenges/{challengeId}/participants`).
///
/// 팀 참여의 실체가 이것이다. 참가 시 예치금(`depositCoins`)이 차감되므로
/// 잔액이 모자라면 서버가 `INSUFFICIENT_COIN`을, 정원이 차면 `CHALLENGE_FULL`을
/// 준다.
class ParticipantService {
  /// POST /api/challenges/{challengeId}/participants. 참가 신청.
  ///
  /// 인증 기준 위치(좌표·반경)를 함께 보내야 한다 — 이후 이 위치로 GPS 인증이
  /// 판정된다. 챌린지의 approvalType이 AUTO면 즉시 CONFIRMED, LEADER면
  /// 방장 승인 전까지 PENDING이다.
  static Future<Participant> apply(
    int challengeId,
    ParticipationRequest request,
  ) async {
    final data = ApiClient.asObject(await ApiClient.post(
      '/challenges/$challengeId/participants',
      body: request.toJson(),
    ));
    Session.currentChallengeId = challengeId;
    return Participant.fromJson(data);
  }

  /// DELETE /api/challenges/{challengeId}/participants/{userId}. 참가 취소.
  ///
  /// 서버가 남의 참가를 취소하지 못하게 막으므로(`UnauthorizedException`)
  /// 항상 내 userId로만 호출한다.
  static Future<void> cancel(int challengeId) async {
    final userId = Session.userId;
    if (userId == null) throw ApiException('로그인이 필요합니다');
    await ApiClient.delete('/challenges/$challengeId/participants/$userId');
    if (Session.currentChallengeId == challengeId) Session.currentChallengeId = null;
  }

  /// GET /api/challenges/{challengeId}/participants?status=PENDING.
  /// 승인 대기 중인 신청자 목록.
  ///
  /// **승인에 필요한 `participantId`를 얻는 유일한 경로다.** 참가 신청 응답을
  /// 받는 건 신청자 본인이지 방장이 아니라서, 방장에게는 이 목록 말고 id를 알
  /// 방법이 없다.
  static Future<List<Participant>> fetchPending(int challengeId) async {
    final data = await ApiClient.get(
      '/challenges/$challengeId/participants',
      query: {'status': 'PENDING'},
    );
    final list = data is List ? data : (data is Map ? data['content'] : null);
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(Participant.fromJson).toList();
  }

  /// POST /api/challenges/{challengeId}/participants/{participantId}/approve.
  /// 방장이 대기 중인 참가 신청을 승인한다(approvalType=LEADER인 챌린지).
  static Future<Participant> approve(int challengeId, int participantId) async {
    final data = ApiClient.asObject(await ApiClient.post(
      '/challenges/$challengeId/participants/$participantId/approve',
    ));
    return Participant.fromJson(data);
  }
}
