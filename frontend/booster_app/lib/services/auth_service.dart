import '../core/api_client.dart';
import '../core/session.dart';
import '../models/app_user.dart';

/// 가입은 성공했는데 뒤이은 자동 로그인이 실패한 상태.
///
/// 서버가 가입 응답에 accessToken을 실어주면 로그인을 아예 부르지 않으므로 이
/// 예외도 나오지 않는다. 토큰을 안 주는 옛 계약을 만났을 때만 남는 경로다.
///
/// 이걸 [ApiException]으로 뭉뚱그리면 화면이 "가입 실패"로 안내하게 되고,
/// 사용자는 이미 만들어진 계정으로 다시 가입을 시도해 이메일 중복 409를 본다.
/// 계정은 이미 있으므로 안내는 "로그인하세요"여야 한다.
class SignupAutoLoginException implements Exception {
  /// 가입에 사용된(정규화된) 이메일. 로그인 화면에 채워 넣는다.
  final String email;

  /// 자동 로그인이 실패한 실제 사유. 사용자에게 덧붙여 보여준다.
  final String reason;

  SignupAutoLoginException(this.email, this.reason);

  @override
  String toString() => 'SignupAutoLoginException($email): $reason';
}

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
      'email': normalizeEmail(email),
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
  /// 가입 응답이 accessToken까지 준다(`SignupResponse`). 그래서 세션은 이
  /// 응답 하나로 채우고 끝낸다 — 로그인을 한 번 더 부르면 BCrypt 해싱이 두 번
  /// 돌아 체감 지연이 두 배가 되고(서버가 토큰을 실어주게 된 이유가 그것이다),
  /// 그 두 번째 호출이 실패하면 계정은 만들어진 채 앱만 실패한 꼴이 된다.
  ///
  /// 토큰을 안 주는 옛 계약을 만났을 때만 로그인으로 넘어간다.
  ///
  /// 서버 검증: 비밀번호 8~64자, 닉네임 1~30자, 이메일 형식(`SignupRequest`).
  static Future<SignupResult> signup(
      String nickname, String email, String password) async {
    final normalized = normalizeEmail(email);
    final data = ApiClient.asObject(await ApiClient.post('/auth/signup', body: {
      'email': normalized,
      'password': password,
      'nickname': nickname.trim(),
    }));

    final result = SignupResult.fromJson(data);

    final token = result.accessToken;
    if (token != null && token.isNotEmpty) {
      Session.set(
        userId: result.userId,
        nickname: result.nickname,
        email: result.email,
        accessToken: token,
      );
    } else {
      // 여기부터는 계정이 이미 만들어진 뒤다. 실패해도 "가입 실패"가 아니다.
      try {
        await login(normalized, password);
      } on ApiException catch (e) {
        throw SignupAutoLoginException(normalized, e.message);
      } catch (_) {
        throw SignupAutoLoginException(normalized, '로그인 중 문제가 발생했어요');
      }
    }

    // 잔액 반영은 세션이 선 뒤에 한다. 먼저 넣으면 위에서 실패했을 때 로그인도
    // 안 된 상태로 가입 보너스 잔액만 남는다. 서버가 안 주면 건드리지 않는다 —
    // 0으로 덮으면 가입 보너스가 화면에서 사라진다.
    final balance = result.coinBalance;
    if (balance != null) Session.coinBalance = balance;
    return result;
  }

  /// 이메일 표기 차이로 로그인이 막히지 않게 한 형태로 맞춘다.
  ///
  /// 가입할 때 `User@a.com`으로 적은 사람이 다음 로그인에서 `user@a.com`을
  /// 치면 서버가 대소문자를 구분하는 순간 "없는 계정"이 된다. 가입과 로그인이
  /// 같은 규칙을 쓰면 그 어긋남 자체가 생기지 않는다.
  static String normalizeEmail(String email) => email.trim().toLowerCase();

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
