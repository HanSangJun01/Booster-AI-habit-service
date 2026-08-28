import 'package:flutter/foundation.dart';

/// 로그인 성공 후 채워지는 현재 사용자 세션.
///
/// 백엔드는 무상태 JWT를 쓴다(`SecurityConfig`, `JwtTokenProvider`). 서버가
/// 토큰을 폐기하지 않으므로 로그아웃은 여기서 토큰을 버리는 것으로 끝난다.
///
/// MVP 범위에서는 메모리에만 유지한다(앱 재시작 시 소실). 재시작 후에도
/// 로그인을 유지하려면 accessToken을 flutter_secure_storage 등에 저장하고 앱
/// 시작 시 복원하는 로직이 추가로 필요하다.
class Session {
  static int? userId;
  static String? nickname;
  static String? email;
  static String? accessToken;

  /// 마지막으로 확인된 코인 잔액. 체크인 응답이 갱신된 잔액을 함께 주기
  /// 때문에(`CheckInResponse.coinBalance` 등), 굳이 다시 조회하지 않고 그
  /// 값으로 갱신해서 화면에 즉시 반영한다.
  ///
  /// 평범한 static 필드로 두면 값이 바뀌어도 위젯이 다시 그려질 이유가 없다.
  /// 실제로 홈 헤더가 `const BoosterHeader()`라 잔액이 500이 돼도 0에 멈춰
  /// 있었다(마이페이지는 자기 상태로 그려서 500이 보이고). 알림 가능한 값으로
  /// 두면 헤더가 const인지 여부와 무관하게 갱신된다.
  static final ValueNotifier<int> coinBalanceListenable = ValueNotifier<int>(0);

  static int get coinBalance => coinBalanceListenable.value;
  static set coinBalance(int value) => coinBalanceListenable.value = value;

  /// 현재 보고 있는 챌린지. 백엔드 모델에서는 챌린지가 최상위이고 팀은 그
  /// 안에서 편성되므로(`GET /api/challenges/{id}/teams`), 팀 관련 화면들이
  /// 기준으로 삼을 챌린지를 여기에 둔다.
  static int? currentChallengeId;

  static bool get isLoggedIn => userId != null;

  static void set({
    required int userId,
    required String nickname,
    String? email,
    String? accessToken,
  }) {
    Session.userId = userId;
    Session.nickname = nickname;
    if (email != null) Session.email = email;
    if (accessToken != null) Session.accessToken = accessToken;
  }

  static void clear() {
    userId = null;
    nickname = null;
    email = null;
    accessToken = null;
    coinBalance = 0;
    currentChallengeId = null;
  }
}
