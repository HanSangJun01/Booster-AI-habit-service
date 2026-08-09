import 'json.dart';

/// 백엔드 `DashboardResponse` (GET /api/dashboard/home).
///
/// 홈 화면이 필요한 값(코인 잔액, 스트릭, 이번 주 성공 횟수, 오늘 상태,
/// 이번 달 달력)을 한 번에 준다. 예전처럼 체크인 목록을 받아 앱에서 직접
/// 집계할 필요가 없다.
class Dashboard {
  final int coinBalance;
  final int currentStreak;
  final int maxStreak;
  final int weeklySuccessCount;

  /// 오늘 개인 체크인 상태(`PersonalCheckInStatus` 문자열). 아직 인증 전이면
  /// 서버가 비어 있는 값을 줄 수 있다.
  final String todayStatus;

  final int calendarYear;
  final int calendarMonth;
  final List<CalendarDay> calendarDays;

  Dashboard({
    required this.coinBalance,
    required this.currentStreak,
    required this.maxStreak,
    required this.weeklySuccessCount,
    required this.todayStatus,
    required this.calendarYear,
    required this.calendarMonth,
    required this.calendarDays,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final streak = json['streak'];
    final calendar = json['calendar'];
    return Dashboard(
      coinBalance: asInt(json['coinBalance']),
      currentStreak: streak is Map<String, dynamic> ? asInt(streak['current']) : 0,
      maxStreak: streak is Map<String, dynamic> ? asInt(streak['max']) : 0,
      weeklySuccessCount: asInt(json['weeklySuccessCount']),
      todayStatus: asString(json['todayStatus']),
      calendarYear: calendar is Map<String, dynamic> ? asInt(calendar['year']) : 0,
      calendarMonth: calendar is Map<String, dynamic> ? asInt(calendar['month']) : 0,
      calendarDays: calendar is Map<String, dynamic>
          ? asObjectList(calendar['days']).map(CalendarDay.fromJson).toList()
          : const [],
    );
  }

  bool get isTodayDone => todayStatus == 'SUCCESS';

  /// 복귀 미션이 걸린 상태 — 홈 화면을 "복귀 모드"로 전환하는 신호다.
  bool get needsRecovery => todayStatus == 'RECOVERY_PENDING';
}

/// `DashboardResponse.CalendarDay` — 달력 한 칸.
class CalendarDay {
  final DateTime? date;

  /// `PersonalCheckInStatus` — SUCCESS | RECOVERY_PENDING | FAILED.
  final String status;

  CalendarDay({this.date, required this.status});

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: asDateOnly(json['date']),
      status: asString(json['status']),
    );
  }

  bool get isSuccess => status == 'SUCCESS';
  bool get isFailed => status == 'FAILED';
  bool get isRecoveryPending => status == 'RECOVERY_PENDING';
}
