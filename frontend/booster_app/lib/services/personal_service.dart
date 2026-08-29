import '../core/api_client.dart';
import '../core/session.dart';
import '../models/ai_verification.dart';
import '../models/check_in.dart';
import '../models/dashboard.dart';
import '../models/personal_location.dart';
import '../models/weekly_goal.dart';

/// 개인 습관 트랙 — 백엔드 A축 (`/api/dashboard`, `/api/personal/check-in`,
/// `/api/users/me/location`).
///
/// 팀/챌린지와 별개로 굴러가는 개인 루틴이다. 인증 기준 위치를 한 번
/// 등록해두면([registerLocation]), 이후 그 반경 안에서 체크인하는 방식이다.
class PersonalService {
  /// GET /api/dashboard/home. 홈 화면 한 번에 채우기(코인/스트릭/주간/달력).
  static Future<Dashboard> fetchDashboard() async {
    final data = ApiClient.asObject(await ApiClient.get('/dashboard/home'));
    final dashboard = Dashboard.fromJson(data);
    Session.coinBalance = dashboard.coinBalance;
    return dashboard;
  }

  /// GET /api/personal/check-in/today. 오늘 인증했는지.
  static Future<TodayStatus> fetchToday() async {
    final data = ApiClient.asObject(await ApiClient.get('/personal/check-in/today'));
    return TodayStatus.fromJson(data);
  }

  /// POST /api/personal/check-in. 실제 기기 좌표로 개인 인증.
  ///
  /// 체크인 생성과 GPS 판정이 한 번에 일어나고, 갱신된 스트릭·코인 잔액까지
  /// 함께 돌아온다. 반경을 벗어났거나 위치가 미등록이면 서버가 에러를 준다.
  static Future<PersonalCheckInResult> checkIn({
    required double latitude,
    required double longitude,
  }) async {
    final data = ApiClient.asObject(await ApiClient.post('/personal/check-in', body: {
      'lat': latitude,
      'lng': longitude,
    }));
    final result = PersonalCheckInResult.fromJson(data);
    Session.coinBalance = result.coinBalance;
    return result;
  }

  /// GET /api/personal/weekly-goal. 주간 목표 + 구제권 현황.
  ///
  /// 상점의 보유 수량·가격 조회처이기도 하다(구제권 전용 조회 API가 없다).
  ///
  /// 인증 기준 위치를 등록하기 전에는 서버가 400 `LOCATION_NOT_REGISTERED`를
  /// 준다. 그건 실패가 아니라 "아직 시작 전"이라서 null로 바꿔 돌려준다 —
  /// 호출부가 이걸 에러로 받으면 위치 등록 전 사용자에게 매번 빨간 토스트가
  /// 뜬다. 그 밖의 400은 진짜 오류라 그대로 올린다.
  static Future<WeeklyGoal?> fetchWeeklyGoal() async {
    try {
      final data = ApiClient.asObject(await ApiClient.get('/personal/weekly-goal'));
      final goal = WeeklyGoal.fromJson(data);
      Session.coinBalance = goal.coinBalance;
      return goal;
    } on ApiException catch (e) {
      if (e.errorCode == 'LOCATION_NOT_REGISTERED') return null;
      rethrow;
    }
  }

  /// PUT /api/personal/weekly-goal. 목표 변경 예약 / 인증 방식 변경.
  ///
  /// **반영 시점이 둘로 갈린다.** [targetDays]는 예약제라 다음 달 1일에 들어가고
  /// (응답의 `pendingTargetDays`로 확인), [verificationType]은 즉시 반영된다.
  /// 화면이 이걸 안내하지 않으면 사용자는 목표를 바꿔놓고 이번 주에 안 바뀌었다고
  /// 여긴다.
  ///
  /// [verificationType]은 `GPS` / `AI` / `GPS_PHOTO_AI`만 받는다. 그 외는 400
  /// `UNSUPPORTED_VERIFICATION_TYPE`.
  static Future<WeeklyGoal> updateWeeklyGoal({
    required int targetDays,
    String? verificationType,
  }) async {
    final data = ApiClient.asObject(await ApiClient.put('/personal/weekly-goal', body: {
      'targetDays': targetDays,
      if (verificationType != null) 'verificationType': verificationType,
    }));
    final goal = WeeklyGoal.fromJson(data);
    Session.coinBalance = goal.coinBalance;
    return goal;
  }

  /// POST /api/personal/check-in/{checkInId}/ai-verification. 사진으로 확정.
  ///
  /// [aiCategory]는 `EXERCISE` 또는 `STUDY`만 유효하다. 개인 트랙에는 카테고리를
  /// 저장하는 곳이 없어서 **앱이 매번 지정해야 한다** — 다른 값을 보내면
  /// `ai-service`가 422를 주고 백엔드가 그걸 500으로 바꾼다
  /// (`ChallengeCategory.aiValueOf` 참조).
  ///
  /// 거절되면([AiVerificationResult.passed] false) 서버가 체크인 레코드를 지워서
  /// 그날 다시 시도할 수 있다. 502가 나면 체크인은 PENDING으로 남으므로 이것도
  /// 재시도 대상이다.
  static Future<AiVerificationResult> verifyPhoto({
    required int checkInId,
    required String filePath,
    required List<int> bytes,
    required String aiCategory,
  }) async {
    final data = ApiClient.asObject(await ApiClient.postImage(
      '/personal/check-in/$checkInId/ai-verification',
      filePath: filePath,
      bytes: bytes,
      fields: {'category': aiCategory},
    ));
    final result = AiVerificationResult.fromJson(data);
    // 개인 응답은 항상 coinBalance를 주지만, 모델이 nullable이므로 방어한다.
    final balance = result.coinBalance;
    if (balance != null) Session.coinBalance = balance;
    return result;
  }

  /// POST /api/personal/rescue. 구제 대기 중인 주를 즉시 구제한다.
  ///
  /// 미리 사두는 구제권([WeeklyGoal.ticketPrice])보다 비싼 사후 구매다
  /// ([WeeklyGoal.lateRescuePrice]). 요청 본문은 없다 — 어느 주를 구제할지는
  /// 서버가 안다.
  ///
  /// 실패 사유가 화면마다 다르게 안내돼야 해서 예외를 그대로 올린다:
  /// 404 `NO_PENDING_RESCUE`(이미 처리됨) · 400 `RESCUE_DEADLINE_PASSED`(기한
  /// 경과) · 400 잔액 부족.
  static Future<WeeklyGoal> rescue() async {
    final data = ApiClient.asObject(await ApiClient.post('/personal/rescue'));
    final goal = WeeklyGoal.fromJson(data);
    Session.coinBalance = goal.coinBalance;
    return goal;
  }

  /// GET /api/users/me/location. 등록된 인증 기준 위치.
  /// 아직 등록 전이면 서버가 404를 주므로 null로 바꿔 돌려준다.
  static Future<PersonalLocation?> fetchLocation() async {
    try {
      final data = ApiClient.asObject(await ApiClient.get('/users/me/location'));
      return PersonalLocation.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /api/users/me/location. 인증 기준 위치 최초 등록.
  static Future<PersonalLocation> registerLocation({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? placeName,
  }) async {
    final data = ApiClient.asObject(await ApiClient.post('/users/me/location',
        body: _locationBody(latitude, longitude, radiusMeters, placeName)));
    return PersonalLocation.fromJson(data);
  }

  /// PUT /api/users/me/location. 이미 등록된 기준 위치 변경.
  static Future<PersonalLocation> updateLocation({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? placeName,
  }) async {
    final data = ApiClient.asObject(await ApiClient.put('/users/me/location',
        body: _locationBody(latitude, longitude, radiusMeters, placeName)));
    return PersonalLocation.fromJson(data);
  }

  /// 위치가 이미 있으면 수정, 없으면 등록. 화면에서는 대개 이쪽만 쓰면 된다.
  static Future<PersonalLocation> saveLocation({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? placeName,
  }) async {
    final existing = await fetchLocation();
    final save = existing == null ? registerLocation : updateLocation;
    return save(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      placeName: placeName,
    );
  }

  static Map<String, dynamic> _locationBody(
      double lat, double lng, int radiusMeters, String? placeName) {
    return {
      'lat': lat,
      'lng': lng,
      'radiusMeters': radiusMeters,
      if (placeName != null && placeName.isNotEmpty) 'placeName': placeName,
    };
  }
}
