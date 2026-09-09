import '../core/api_client.dart';
import '../core/session.dart';
import '../models/app_user.dart';

/// 내 정보/코인 — 백엔드 `UserController` (`/api/users/me`).
///
/// 사용자를 id로 조회하는 엔드포인트는 없다. JWT의 subject가 곧 userId라서
/// 서버가 "나"를 알아서 판별한다.
///
/// 프로필 수정(닉네임/이미지)과 알림 설정 API는 백엔드에 **없다**.
class UserService {
  /// GET /api/users/me. 마이페이지 정보.
  static Future<AppUser> fetchMe() async {
    final data = ApiClient.asObject(await ApiClient.get('/users/me'));
    final user = AppUser.fromJson(data);
    Session.nickname = user.nickname;
    Session.email = user.email;
    Session.coinBalance = user.coinBalance;
    return user;
  }

  /// GET /api/users/me/coins. 코인 변동 내역(페이징).
  /// 서버가 size를 1~100으로 클램프한다.
  static Future<CoinHistory> fetchCoinHistory({int page = 0, int size = 20}) async {
    final data = ApiClient.asObject(await ApiClient.get('/users/me/coins', query: {
      'page': page,
      'size': size,
    }));
    return CoinHistory.fromJson(data);
  }

  /// DELETE /api/users/me. 회원 탈퇴. 성공 시 세션을 비운다.
  static Future<void> withdraw() async {
    await ApiClient.delete('/users/me');
    Session.clear();
  }
}
