import '../core/api_client.dart';
import '../core/session.dart';
import '../models/app_user.dart';

/// 회원가입/로그인 — 백엔드 `AuthController` (`/api/auth/**`).
///
/// 이 경로만 인증 없이 열려 있고(`SecurityConfig`), 나머지 모든 엔드포인트는
/// 로그인으로 받은 accessToken이 있어야 한다.
///
/// 목업 폴백은 두지 않는다. 서버가 없으면 없다고 알려주는 편이,
/// 성공한 것처럼 보이게 만드는 것보다 낫다.
class AuthService {
  /// POST /api/auth/login. 성공하면 Session에 사용자/토큰을 채운다.
  static Future<AuthResult> login(String email, String password) async {
    final data = ApiClient.asObject(await ApiClient.post('/auth/login', body: {
      'email': email,
      'password': password,
    }));

    final result = AuthResult.fromJson(data);
    Session.set(
      userId: result.userId,
      nickname: result.nickname,
      email: result.email,
      accessToken: result.accessToken,
    );
    return result;
  }

  /// POST /api/auth/signup.
  ///
  /// 가입 응답에는 accessToken이 없어서(`SignupResponse`) 그대로 두면 이후
  /// 요청이 전부 401이 된다. 그래서 가입 직후 같은 자격증명으로 로그인까지
  /// 이어서 수행하고, 세션은 로그인 응답으로 채운다.
  ///
  /// 서버 검증: 비밀번호 8~64자, 닉네임 1~30자, 이메일 형식.
  static Future<SignupResult> signup(
      String nickname, String email, String password) async {
    final data = ApiClient.asObject(await ApiClient.post('/auth/signup', body: {
      'email': email,
      'password': password,
      'nickname': nickname,
    }));

    final result = SignupResult.fromJson(data);
    // 잔액 반영은 로그인까지 성공한 뒤에 한다. 먼저 넣으면 로그인이 실패했을 때
    // 로그인도 안 된 상태로 가입 보너스 잔액만 남는다.
    await login(email, password);
    Session.coinBalance = result.coinBalance;
    return result;
  }

  /// POST /api/auth/logout.
  ///
  /// 무상태 JWT라 서버가 토큰을 폐기하지 않는다 — 실제 로그아웃은 여기서
  /// 세션을 비우는 것이다. 서버 호출이 실패해도 로컬 세션은 반드시 지운다.
  static Future<void> logout() async {
    try {
      await ApiClient.post('/auth/logout');
    } on ApiException {
      // 로그아웃 통지 실패는 사용자가 할 수 있는 게 없다. 조용히 넘어간다.
    } finally {
      Session.clear();
    }
  }
}
