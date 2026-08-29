import 'json.dart';

/// 주간 목표 현황 — `GET /api/personal/weekly-goal` (A축이라 래퍼 없는 raw JSON).
///
/// 이름은 '주간 목표'지만 실제로는 A축 상태를 한 번에 내려주는 창구다. 상점이
/// 보여줘야 할 **구제권 보유 수량·가격·잔액이 전부 여기 있고**(구제권 전용
/// 조회 API가 따로 없다), 구제 안내 팝업을 띄울지도 이 응답으로 판단한다.
///
/// 그래서 상점 화면과 홈 화면이 같은 응답을 본다. 가격을 앱에 하드코딩하면
/// 서버가 값을 바꿨을 때 "표시가 800인데 결제는 1,000"이 되므로,
/// [ticketPrice]·[lateRescuePrice]는 항상 이 응답에서 읽는다.
class WeeklyGoal {
  /// 이번 주 시작일(월요일).
  final DateTime? weekStart;

  /// 이번 주에 채워야 하는 인증 횟수(2~7).
  final int targetDays;

  /// 예약된 목표. null이 아니면 **다음 달 1일부터** 이 값으로 바뀐다.
  /// 목표 변경이 즉시 반영되지 않는다는 걸 화면이 안내해야 한다.
  final int? pendingTargetDays;

  /// 이번 주에 지금까지 성공한 횟수.
  final int successCount;

  /// 이번 주에 남은 일수.
  final int remainingDays;

  /// 보유 구제권 합계([freeTickets] + [paidTickets]).
  final int recoveryTickets;

  /// 무료로 받은 분. **이번 달 말에 소멸한다.**
  final int freeTickets;

  /// 구매한 분. 소멸하지 않는다. 소멸 규칙이 달라서 화면이 둘을 나눠 보여준다.
  final int paidTickets;

  /// 구제권 판매가. **앱에 하드코딩하지 말 것.**
  final int ticketPrice;

  final int coinBalance;

  /// `GPS` / `AI` / `GPS_PHOTO_AI`. 목표와 달리 즉시 반영된다.
  final String verificationType;

  /// 지난주 채점 결과(`ACHIEVED` / `FAILED` / `RESCUED` 등). 아직 없으면 null.
  final String? lastWeekResult;

  /// 구제 대기 중인 주의 시작일. **null이 아니면 구제 안내 팝업을 띄운다.**
  final DateTime? pendingRescueWeek;

  /// 그 주를 구제할 수 있는 기한. 지나면 스트릭 0 + 코인 차감이 확정된다.
  final DateTime? rescueDeadline;

  /// 사후 구제 가격. 미리 사두는 [ticketPrice]보다 비싸다.
  final int lateRescuePrice;

  const WeeklyGoal({
    required this.weekStart,
    required this.targetDays,
    required this.pendingTargetDays,
    required this.successCount,
    required this.remainingDays,
    required this.recoveryTickets,
    required this.freeTickets,
    required this.paidTickets,
    required this.ticketPrice,
    required this.coinBalance,
    required this.verificationType,
    required this.lastWeekResult,
    required this.pendingRescueWeek,
    required this.rescueDeadline,
    required this.lateRescuePrice,
  });

  /// 구제 안내 팝업을 띄워야 하는 상태인지.
  ///
  /// 기한까지 함께 확인한다 — 대기 주만 있고 기한을 못 읽으면 팝업이 "언제까지"를
  /// 말할 수 없고, 그러면 사용자가 급한 일인지 판단할 근거가 없다.
  bool get needsRescue => pendingRescueWeek != null && rescueDeadline != null;

  /// 구제 대기 주의 마지막 날(월요일 시작 + 6일).
  DateTime? get pendingRescueWeekEnd =>
      pendingRescueWeek?.add(const Duration(days: 6));

  factory WeeklyGoal.fromJson(Map<String, dynamic> json) {
    final free = asInt(json['freeTickets']);
    final paid = asInt(json['paidTickets']);
    return WeeklyGoal(
      weekStart: asDateOnly(json['weekStart']),
      targetDays: asInt(json['targetDays']),
      pendingTargetDays: asIntOrNull(json['pendingTargetDays']),
      successCount: asInt(json['successCount']),
      remainingDays: asInt(json['remainingDays']),
      // 합계를 서버가 안 주면 무료+구매로 메운다. 보유 수량은 "몇 개 있나"만
      // 맞으면 되는 값이라, 없다고 0으로 떨어뜨리면 있는 걸 없다고 말하게 된다.
      recoveryTickets: asInt(json['recoveryTickets'], fallback: free + paid),
      freeTickets: free,
      paidTickets: paid,
      ticketPrice: asInt(json['ticketPrice']),
      coinBalance: asInt(json['coinBalance']),
      verificationType: asString(json['verificationType'], fallback: 'GPS'),
      lastWeekResult: json['lastWeekResult'] as String?,
      pendingRescueWeek: asDateOnly(json['pendingRescueWeek']),
      rescueDeadline: asDateTime(json['rescueDeadline']),
      lateRescuePrice: asInt(json['lateRescuePrice']),
    );
  }
}

/// `POST /api/personal/recovery-tickets` 응답 — 구제권 구매 결과.
///
/// 구매가 성공했을 때만 온다. [price]는 이번에 실제로 빠져나간 금액이라,
/// 화면이 보여준 가격과 다를 수 있다(서버가 값을 바꾼 직후). 안내 문구는
/// 이 값을 기준으로 쓴다.
class RecoveryTicketPurchase {
  /// 구매 후 보유 구제권 총 수량.
  final int recoveryTickets;

  /// 이번 구매에 지불한 금액.
  final int price;

  /// 구매 후 코인 잔액.
  final int coinBalance;

  const RecoveryTicketPurchase({
    required this.recoveryTickets,
    required this.price,
    required this.coinBalance,
  });

  factory RecoveryTicketPurchase.fromJson(Map<String, dynamic> json) {
    return RecoveryTicketPurchase(
      recoveryTickets: asInt(json['recoveryTickets']),
      price: asInt(json['price']),
      coinBalance: asInt(json['coinBalance']),
    );
  }
}
