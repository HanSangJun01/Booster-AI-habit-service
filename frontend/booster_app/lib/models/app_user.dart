import 'json.dart';

/// 백엔드 `MyPageResponse` (GET /api/users/me).
class AppUser {
  final int userId;
  final String email;
  final String nickname;
  final DateTime? joinedAt;

  /// 누적 출석일수(개인 체크인 성공 횟수).
  final int totalAttendance;
  final int coinBalance;

  AppUser({
    required this.userId,
    required this.email,
    required this.nickname,
    this.joinedAt,
    required this.totalAttendance,
    required this.coinBalance,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: asInt(json['userId']),
      email: asString(json['email']),
      nickname: asString(json['nickname']),
      joinedAt: asDateTime(json['joinedAt']),
      totalAttendance: asInt(json['totalAttendance']),
      coinBalance: asInt(json['coinBalance']),
    );
  }
}

/// 백엔드 `LoginResponse` (POST /api/auth/login).
class AuthResult {
  final int userId;
  final String email;
  final String nickname;
  final String accessToken;

  AuthResult({
    required this.userId,
    required this.email,
    required this.nickname,
    required this.accessToken,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      userId: asInt(json['userId']),
      email: asString(json['email']),
      nickname: asString(json['nickname']),
      accessToken: asString(json['accessToken']),
    );
  }
}

/// 백엔드 `SignupResponse` (POST /api/auth/signup).
///
/// 로그인 응답과 달리 accessToken이 없다 — 가입 직후 로그인을 한 번 더
/// 호출해야 인증이 필요한 요청을 보낼 수 있다.
class SignupResult {
  final int userId;
  final String email;
  final String nickname;

  /// 가입 보너스(`SIGNUP_BONUS` +500)가 반영된 초기 잔액.
  final int coinBalance;
  final DateTime? joinedAt;

  SignupResult({
    required this.userId,
    required this.email,
    required this.nickname,
    required this.coinBalance,
    this.joinedAt,
  });

  factory SignupResult.fromJson(Map<String, dynamic> json) {
    return SignupResult(
      userId: asInt(json['userId']),
      email: asString(json['email']),
      nickname: asString(json['nickname']),
      coinBalance: asInt(json['coinBalance']),
      joinedAt: asDateTime(json['joinedAt']),
    );
  }
}

/// 백엔드 `CoinTransactionResponse` (GET /api/users/me/coins 항목).
class CoinTransaction {
  /// `CoinTransactionReason`.
  ///
  /// RECOVERY_SUCCESS / RECOVERY_FAILURE는 폐지된 복귀 미션의 사유다. 백엔드
  /// enum에는 남아 있고 예전 거래 기록도 그대로라, 내역 화면이 원문 문자열을
  /// 그대로 노출하지 않도록 라벨은 유지한다.
  final String type;
  final int amount;
  final int balanceAfter;
  final int? referenceId;
  final DateTime? createdAt;

  CoinTransaction({
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.referenceId,
    this.createdAt,
  });

  factory CoinTransaction.fromJson(Map<String, dynamic> json) {
    return CoinTransaction(
      type: asString(json['type']),
      amount: asInt(json['amount']),
      balanceAfter: asInt(json['balanceAfter']),
      referenceId: asIntOrNull(json['referenceId']),
      createdAt: asDateTime(json['createdAt']),
    );
  }

  bool get isGain => amount > 0;

  /// 코인 내역에 보여줄 한국어 사유.
  String get label {
    switch (type) {
      case 'SIGNUP_BONUS':
        return '가입 보너스';
      case 'STREAK_REWARD':
        return '연속 인증 보상';
      // 폐지된 사유 — 지난 기록에만 남는다.
      case 'RECOVERY_SUCCESS':
        return '복귀 미션 성공';
      case 'RECOVERY_FAILURE':
        return '복귀 미션 실패';
      // 주간 목표 모델에서 새로 생긴 사유. 앱이 주간 목표를 아직 안 붙였어도
      // 서버 스케줄러가 기록을 남기므로 내역 화면에 그대로 올라온다.
      case 'WEEKLY_MISS_PENALTY':
        return '주간 목표 미달';
      case 'RECOVERY_TICKET_PURCHASE':
        return '구제권 구매';
      case 'LATE_RESCUE_PURCHASE':
        return '구제권 사후 구매';
      case 'CHALLENGE_DEPOSIT':
        return '챌린지 예치금';
      case 'SETTLEMENT_WIN':
        return '정산 보상';
      case 'DEPOSIT_REFUND':
        return '예치금 환불';
      case 'DEPOSIT_CANCEL_REFUND':
        return '참가 취소 환불';
      default:
        return type;
    }
  }
}

/// 백엔드 `CoinHistoryResponse` (GET /api/users/me/coins).
class CoinHistory {
  final List<CoinTransaction> transactions;
  final int totalCount;

  CoinHistory({required this.transactions, required this.totalCount});

  static const empty = CoinHistory._empty();
  const CoinHistory._empty()
      : transactions = const [],
        totalCount = 0;

  factory CoinHistory.fromJson(Map<String, dynamic> json) {
    return CoinHistory(
      transactions:
          asObjectList(json['transactions']).map(CoinTransaction.fromJson).toList(),
      totalCount: asInt(json['totalCount']),
    );
  }
}
