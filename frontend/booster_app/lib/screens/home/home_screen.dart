import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/app_user.dart';
import '../../models/dashboard.dart';
import '../../models/personal_location.dart';
import '../../models/weekly_goal.dart';
import '../../services/personal_service.dart';
import '../../services/user_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'personal_create_screen.dart';
import 'rescue_notice.dart';
import 'weekly_goal_screen.dart';

/// 홈 — 개인 습관 트랙.
///
/// 백엔드에는 "개인 챌린지"라는 엔티티가 없다. 개인 트랙은
/// 인증 기준 위치(`/api/users/me/location`) + 일일 체크인
/// (`/api/personal/check-in`) + 스트릭으로 이뤄지고, 이 화면이 필요한 수치는
/// `GET /api/dashboard/home` 한 번으로 전부 받는다.
///
/// 그래서 "시작 전" 상태의 기준은 챌린지 유무가 아니라 **인증 기준 위치 등록
/// 여부**다. 위치가 없으면 체크인 자체가 불가능하다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _loading = true;
  Dashboard? _dashboard;
  PersonalLocation? _location;
  int _totalAttendance = 0;
  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  /// 이번 주 목표. 진행률의 분모이자 구제 대기 여부의 출처다.
  WeeklyGoal? _goal;

  /// 구제 안내 팝업이 떠 있는 동안 또 띄우지 않게 하는 빗장.
  ///
  /// 홈 진입과 포그라운드 복귀가 겹치면 같은 팝업이 두 겹으로 쌓인다. 뒤에
  /// 깔린 쪽은 [나중에]를 눌러도 안 사라져서 사용자가 갇힌다.
  bool _rescueNoticeOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱이 다시 앞으로 나올 때 구제 대기 상태를 다시 본다.
  ///
  /// 홈 탭 진입만으로는 놓친다 — 앱을 켜둔 채 날짜가 넘어가면 이 화면의
  /// didChangeDependencies는 다시 안 불리는데, 구제 기한은 2일뿐이다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncRescueNotice());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold는 탭을 IndexedStack으로 유지해서, 다른 탭에서 상태가 바뀌어도
    // 이 화면의 initState가 다시 안 불린다. 홈 탭(index 0)이 "새로 활성화"될
    // 때마다 다시 불러와서 최신 상태를 본다.
    const homeTabIndex = 0;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == homeTabIndex && _lastActiveTabIndex != homeTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 서로 의존하지 않는 조회라 한꺼번에 보낸다.
      final results = await Future.wait([
        PersonalService.fetchDashboard(),
        PersonalService.fetchLocation(),
        UserService.fetchMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Dashboard;
        _location = results[1] as PersonalLocation?;
        _totalAttendance = (results[2] as AppUser).totalAttendance;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      // ApiException이 아닌 예외(플러그인 오류 등)가 나면 _loading이 true로
      // 남는데, 그러면 RefreshIndicator 자체가 안 그려져서 당겨서 새로고침도
      // 못 한다 — 앱을 껐다 켜는 것 말고 빠져나갈 길이 없어진다.
      if (mounted) setState(() => _loading = false);
    }
    // 팝업을 기다리지 않는다 — 기다리면 당겨서 새로고침 표시가 팝업이 닫힐
    // 때까지 계속 돈다.
    unawaited(_syncRescueNotice());
  }

  /// 지난주 목표를 못 채워 구제 대기 중이면 안내 팝업을 띄운다.
  ///
  /// 기한이 지나면 서버가 스트릭 0 + 코인 −500으로 확정해버린다. 앱이 알리지
  /// 않으면 사용자는 그걸 새벽에 예고 없이 맞는다.
  Future<void> _syncRescueNotice() async {
    if (_rescueNoticeOpen) return;

    WeeklyGoal? goal;
    try {
      goal = await PersonalService.fetchWeeklyGoal();
    } on ApiException {
      // 주간 목표는 홈에 얹히는 정보라, 못 읽었다고 토스트를 띄우면 정작
      // 봐야 할 대시보드 위에 에러만 겹친다. 다음 진입 때 다시 본다.
      return;
    }
    if (!mounted) return;
    setState(() => _goal = goal);
    if (goal == null || !goal.needsRescue) return;

    _rescueNoticeOpen = true;
    try {
      final changed = await showRescueNotice(context, goal);
      // 구제했거나 서버가 이미 처리했다고 답한 경우. 화면에 남은 스트릭·코인이
      // 낡았다는 뜻이라 다시 읽는다.
      if (changed && mounted) await _load();
    } finally {
      _rescueNoticeOpen = false;
    }
  }

  Future<void> _onLocationRegistered(PersonalLocation location) async {
    setState(() => _location = location);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoosterHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                  : (_location == null ? _emptyBody() : _activeBody()),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 진행 중 ─────────────────────────
  Widget _activeBody() {
    final dashboard = _dashboard;
    if (dashboard == null) return _emptyBody();
    return RefreshIndicator(
      onRefresh: _load,
      color: BC.oMain,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        children: [
          _hero(dashboard),
          const SizedBox(height: 14),
          _weeklyGoalCard(),
          const SizedBox(height: 14),
          _statCard1(dashboard),
          const SizedBox(height: 14),
          _statCard2(dashboard),
          const SizedBox(height: 14),
          CalendarCard(
            year: dashboard.calendarYear,
            month: dashboard.calendarMonth,
            days: dashboard.calendarDays,
          ),
          const SizedBox(height: 14),
          _locationCard(),
        ],
      ),
    );
  }

  /// 주간 진행률.
  ///
  /// 분모는 사용자가 정한 목표 횟수다. 7로 박아두면 목표가 주 3회인 사람에게
  /// 3/7=43%로 보여서, 목표를 다 채운 주에도 절반도 못 한 것처럼 읽힌다.
  ///
  /// 목표를 아직 못 읽었으면(위치 미등록·조회 실패) 7로 둔다 — 채점 주기가
  /// 일주일이라 최댓값이고, 실제보다 높게 보여 안심시키는 것보다 낫다.
  double _weeklyPct(Dashboard dashboard) {
    final target = _goal?.targetDays ?? 7;
    return (dashboard.weeklySuccessCount / (target == 0 ? 7 : target))
        .clamp(0, 1)
        .toDouble();
  }

  String _statusText(Dashboard dashboard) =>
      dashboard.isTodayDone ? '오늘 인증을 마쳤어요' : '오늘 아직 인증하지 않았어요';

  Widget _hero(Dashboard dashboard) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        gradient: BC.heroGrad,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: BC.o2.withValues(alpha: .32),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('오늘의 습관',
                style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(_location?.displayName ?? '인증 장소',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('보유 코인',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const CoinDot(size: 24),
                        const SizedBox(width: 8),
                        Text(CoinPill.format(dashboard.coinBalance),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text('코인',
                              style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(_statusText(dashboard),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ring(_weeklyPct(dashboard)),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => MainNavScope.of(context).select(2),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.calendar_today_rounded, color: BC.oMain, size: 18),
                  SizedBox(width: 8),
                  Text('오늘 인증하러 가기',
                      style: TextStyle(
                          color: BC.oMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: BC.oMain, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double pct) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(104, 104), painter: _RingPainter(pct)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('이번 주',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text('${(pct * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  /// 주간 목표 요약 + 설정 진입점.
  ///
  /// 서버는 "주 N회"로 채점하고 못 채우면 스트릭 0 + 코인 −500까지 간다. 그
  /// 기준이 화면 어디에도 없으면 사용자는 무엇을 채워야 하는지 모른 채
  /// 채점당한다.
  Widget _weeklyGoalCard() {
    final goal = _goal;
    return GestureDetector(
      onTap: _openWeeklyGoal,
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
              child: const Icon(Icons.flag_rounded, size: 21, color: BC.oMain),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('주간 목표',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    goal == null
                        ? '목표를 정하면 여기에 나와요'
                        : '주 ${goal.targetDays}회 중 ${goal.successCount}회 · ${goal.remainingDays}일 남음',
                    style: const TextStyle(fontSize: 12.5, color: BC.ink3),
                  ),
                  if (goal?.pendingTargetDays != null) ...[
                    const SizedBox(height: 4),
                    // 목표 변경은 예약제라 이번 달엔 안 바뀐다. 말해주지 않으면
                    // 사용자는 저장이 안 먹은 줄 안다.
                    MiniTag('다음 달부터 주 ${goal!.pendingTargetDays}회',
                        bg: BC.blueSoft, fg: BC.blue),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BC.ink3),
          ],
        ),
      ),
    );
  }

  Future<void> _openWeeklyGoal() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WeeklyGoalScreen()));
    if (mounted) await _load();
  }

  Widget _statCard1(Dashboard dashboard) {
    return AppCard(
      child: Row(
        children: [
          // 스트릭은 **연속 일수가 아니라 누적 인증 횟수**다. 인증할 때마다 +1이고
          // 날짜가 하루 비어도 끊기지 않는다 — 초기화는 주간 목표 미달이 FAILED로
          // 확정될 때만 일어난다. '연속 N일'로 쓰면 하루 걸러 인증한 사용자에게
          // 앱이 거짓말을 하게 된다.
          _stat(
            icon: Icons.local_fire_department_rounded,
            iconColor: BC.oMain,
            iconBg: BC.oSoft,
            label: '누적 인증',
            value: '${dashboard.currentStreak}',
            unit: '회',
            valueColor: BC.oMain,
            tag: '최고 기록 ${dashboard.maxStreak}회',
          ),
          _divider(),
          _stat(
            icon: Icons.event_available_rounded,
            iconColor: BC.green,
            iconBg: BC.greenSoft,
            label: '이번 주 성공일',
            value: '${dashboard.weeklySuccessCount}',
            unit: '일',
            valueColor: BC.green,
            tag: '이번 주 인증 기록',
            tagHi: true,
          ),
        ],
      ),
    );
  }

  Widget _statCard2(Dashboard dashboard) {
    // 백엔드는 currentStreak가 7의 배수가 될 때마다 STREAK_REWARD(+100)를
    // 지급한다. 7·14·21…"회"이지 7일이 아니다 — 남은 양도 횟수로 센다.
    const milestoneCount = 7;
    final positionInCycle = dashboard.currentStreak % milestoneCount;
    final countToNextReward = milestoneCount - positionInCycle;
    final progress = positionInCycle / milestoneCount;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stat(
            icon: Icons.emoji_events_rounded,
            iconColor: BC.oMain,
            iconBg: BC.oSoft,
            label: '누적 출석',
            value: '$_totalAttendance',
            unit: '일',
            valueColor: BC.ink,
            tag: '가입 후 전체',
          ),
          _divider(),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.star_rounded, size: 24, color: BC.oMain),
                ),
                const SizedBox(height: 6),
                const Text('다음 보상', style: TextStyle(fontSize: 12.5, color: BC.ink2)),
                const Text('+100',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, color: BC.oMain)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: BC.line,
                    valueColor: const AlwaysStoppedAnimation(BC.oMain),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('7회마다',
                        style: TextStyle(fontSize: 11, color: BC.ink3)),
                    Text('$countToNextReward회 남음',
                        style: const TextStyle(
                            fontSize: 11, color: BC.oMain, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    required String unit,
    required Color valueColor,
    required String tag,
    bool tagHi = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 23, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, color: BC.ink2)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, color: valueColor)),
              Text(unit, style: const TextStyle(fontSize: 14, color: BC.ink2)),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: tagHi ? BC.oSoft : BC.bg, borderRadius: BorderRadius.circular(999)),
            child: Text(tag,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tagHi ? BC.oMain : BC.ink2)),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1,
      height: 96,
      color: BC.line,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  /// 등록된 인증 기준 위치. 여기서 바로 변경할 수 있게 해둔다 — 위치를 잘못
  /// 잡으면 인증이 계속 실패하기 때문이다.
  Widget _locationCard() {
    final location = _location;
    if (location == null) return const SizedBox.shrink();
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.place_rounded, size: 21, color: BC.oMain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('인증 기준 장소',
                    style: TextStyle(fontSize: 12.5, color: BC.ink3)),
                Text(location.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text('반경 ${location.radiusMeters}m 안에서 인증할 수 있어요',
                    style: const TextStyle(fontSize: 12, color: BC.ink3)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              final updated = await Navigator.of(context).push<PersonalLocation>(
                  MaterialPageRoute(builder: (_) => PersonalCreateScreen(current: location)));
              if (updated != null && mounted) _onLocationRegistered(updated);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('변경',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: BC.oMain)),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 시작 전(위치 미등록) ─────────────────────────
  Widget _emptyBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        DottedBox(
          child: SizedBox(
            height: 220,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.place_outlined, size: 34, color: BC.oMain),
                  SizedBox(height: 8),
                  Text('인증 장소를 등록하세요',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: BC.oMain)),
                  SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('등록한 위치 반경 안에서만 GPS 인증이 가능해요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: BC.ink2)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: const [
            Icon(Icons.campaign_rounded, size: 20, color: BC.oMain),
            SizedBox(width: 7),
            Text('시작 전 알아두기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: BC.oMain)),
          ],
        ),
        const SizedBox(height: 12),
        // 아래 금액은 백엔드 `CoinTransactionReason`에 정의된 실제 값이다.
        //
        // 복귀 미션(성공 -50 / 실패 -100) 안내는 뺐다 — 백엔드에서 복귀가
        // 폐지되면서 없는 규칙이 됐다. 대신 들어온 주간 목표 미달 페널티
        // (WEEKLY_MISS_PENALTY)는 앱이 주간 목표를 아직 안 붙여서, 금액을
        // 지어내지 않고 연동할 때 함께 넣는다.
        _infoCard(Icons.local_fire_department_rounded, BC.oSoft, BC.oMain, '7회마다',
            '+100 코인', '인증 횟수가 7회 쌓일 때마다 보상을 받아요. 하루를 걸러도 끊기지 않아요.'),
        const SizedBox(height: 20),
        PrimaryButton(
          label: '인증 장소 등록하기',
          trailingIcon: Icons.chevron_right_rounded,
          onTap: () async {
            final created = await Navigator.of(context).push<PersonalLocation>(
                MaterialPageRoute(builder: (_) => const PersonalCreateScreen()));
            if (created != null && mounted) _onLocationRegistered(created);
          },
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, Color iconBg, Color iconColor, String title, String amt,
      String desc) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 23, color: iconColor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text(amt,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800, color: BC.oMain)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 진행률 링 페인터 ─────────────────────────
class _RingPainter extends CustomPainter {
  final double pct;
  _RingPainter(this.pct);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    final fg = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * pct, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ───────────────────────── 점선 박스 ─────────────────────────
class DottedBox extends StatelessWidget {
  final Widget child;
  const DottedBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BC.oSoft2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(18));
    final path = Path()..addRRect(rrect);
    const dash = 7.0, gap = 6.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ───────────────────────── 캘린더 카드 ─────────────────────────
/// 서버가 `GET /api/dashboard/home`으로 한 달치 상태를 통째로 준다
/// (`calendar.year/month/days`). 앱이 체크인 목록을 받아 직접 집계하던 예전
/// 방식과 달리, 여기서는 받은 값을 그리기만 한다 — 그래서 월 이동도 없다.
class CalendarCard extends StatelessWidget {
  final int year;
  final int month;
  final List<CalendarDay> days;

  const CalendarCard({
    super.key,
    required this.year,
    required this.month,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    if (year == 0 || month == 0) return const SizedBox.shrink();

    final first = DateTime(year, month, 1).weekday % 7; // 일=0
    final dayCount = DateTime(year, month + 1, 0).day;

    final done = <int>{};
    final failed = <int>{};
    for (final day in days) {
      final date = day.date;
      if (date == null || date.year != year || date.month != month) continue;
      if (day.isSuccess) {
        done.add(date.day);
      } else if (day.isFailed) {
        failed.add(date.day);
      }
    }

    final cells = <Widget>[];
    for (int k = 0; k < first; k++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= dayCount; d++) {
      Color bg;
      Color fg;
      if (done.contains(d)) {
        bg = BC.green;
        fg = Colors.white;
      } else if (failed.contains(d)) {
        bg = BC.oMain;
        fg = Colors.white;
      } else {
        bg = const Color(0xFFECECEE);
        fg = BC.ink3;
      }
      cells.add(Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text('$d',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ),
      ));
    }

    return AppCard(
      child: Column(
        children: [
          Text('$month월 기록',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: const [
              _Weekday('일'),
              _Weekday('월'),
              _Weekday('화'),
              _Weekday('수'),
              _Weekday('목'),
              _Weekday('금'),
              _Weekday('토'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            children: cells,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _Legend(BC.green, '성공'),
              SizedBox(width: 14),
              _Legend(BC.oMain, '실패'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Weekday extends StatelessWidget {
  final String label;
  const _Weekday(this.label);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(label, style: const TextStyle(fontSize: 12, color: BC.ink3)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11.5, color: BC.ink2)),
      ],
    );
  }
}
