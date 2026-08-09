import '../core/api_client.dart';
import '../core/session.dart';
import '../models/check_in.dart';
import '../models/dashboard.dart';
import '../models/personal_location.dart';

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
