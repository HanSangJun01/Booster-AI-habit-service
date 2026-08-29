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
}

/// `DashboardResponse.CalendarDay` — 달력 한 칸.
class CalendarDay {
  final DateTime? date;

  /// `PersonalCheckInStatus` — SUCCESS | PENDING.
  ///
  /// 복귀 미션이 폐지되면서 RECOVERY_PENDING이 사라졌고, "그날 안 했다"는 이제
  /// 상태값이 아니라 **레코드 부재**로 표현된다. PENDING은 AI 사진 판정을
  /// 기다리는 중이라는 뜻이다(앱은 아직 AI 인증을 붙이지 않았다).
  final String status;

  CalendarDay({this.date, required this.status});

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: asDateOnly(json['date']),
      status: asString(json['status']),
    );
  }

  bool get isSuccess => status == 'SUCCESS';

  /// 새 백엔드는 개인 체크인에 FAILED를 남기지 않는다(V14가 기존 행도 지웠다).
  /// 예전 서버를 보는 동안에만 값이 올 수 있어 판정만 남겨둔다.
  bool get isFailed => status == 'FAILED';
}
