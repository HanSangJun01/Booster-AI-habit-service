import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/challenge.dart';
import '../../models/check_in.dart';
import '../../services/challenge_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'personal_create_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  Challenge? _challenge;
  List<CheckIn> _checkIns = [];
  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold는 탭을 IndexedStack으로 유지해서, 다른 탭(팀 생성 등)에서
    // 상태가 바뀌어도 이 화면의 initState가 다시 안 불린다. 홈 탭(index 0)이
    // "새로 활성화"될 때마다 다시 불러와서 최신 상태를 본다.
    const homeTabIndex = 0;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == homeTabIndex && _lastActiveTabIndex != homeTabIndex) {
      _loadChallenge();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _loadChallenge() async {
    setState(() => _loading = true);
    try {
      final challenge = await ChallengeService.fetchActiveChallenge();
      final checkIns = challenge == null
          ? <CheckIn>[]
          : await ChallengeService.fetchCheckIns(challenge.challengeId);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _checkIns = checkIns;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // statusCode == null: 서버 연결 자체가 안 되는 경우(지금처럼 백엔드가
      // 없을 때)만 "챌린지 생성 전" 빈 상태로 조용히 대체한다. statusCode가
      // 있으면 서버가 실제 에러를 준 것이라 빈 화면으로 감추지 않고 토스트로
      // 드러낸다 — 나중에 진짜 백엔드 연동 시 401/500 같은 에러를 놓치지 않기 위함.
      if (e.statusCode != null) showBoosterToast(context, e.message);
      setState(() {
        _challenge = null;
        _checkIns = [];
        _loading = false;
      });
    }
  }

  Future<void> _onChallengeCreated(Challenge created) async {
    List<CheckIn> checkIns = [];
    try {
      checkIns = await ChallengeService.fetchCheckIns(created.challengeId);
    } on ApiException catch (_) {
      // 방금 만든 챌린지라 체크인이 없는 게 정상 — 조회 실패해도 빈 목록으로 진행.
    }
    if (!mounted) return;
    setState(() {
      _challenge = created;
      _checkIns = checkIns;
      _loading = false;
    });
  }

  // ───────────────────────── 체크인 기반 통계 계산 ─────────────────────────
  int get _currentStreak {
    final success = _checkIns.where((c) => c.isSuccess).map((c) => c.date).toSet();
    var day = DateTime.now();
    var streak = 0;
    while (success.contains(DateTime(day.year, day.month, day.day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get _bestStreak {
    final days = _checkIns.where((c) => c.isSuccess).map((c) => c.date).toList()
      ..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && d.difference(prev).inDays == 1) {
        cur++;
      } else {
        cur = 1;
      }
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  int get _weekSuccessCount {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7)); // 일요일 시작
    final weekEnd = weekStart.add(const Duration(days: 6));
    return _checkIns
        .where((c) => c.isSuccess && !c.date.isBefore(weekStart) && !c.date.isAfter(weekEnd))
        .length;
  }

  int get _totalSuccessCount => _checkIns.where((c) => c.isSuccess).length;

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
                  : (_challenge == null ? _emptyBody() : _activeBody()),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 진행 중 / 복귀 ─────────────────────────
  Widget _activeBody() {
    final challenge = _challenge!;
    // TODO: 체크인 지연/실패 여부로 복귀 모드를 판정하는 API 필드가 정해지면 교체.
    const recovery = false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _hero(recovery, challenge),
        const SizedBox(height: 14),
        _statCard1(recovery),
        const SizedBox(height: 14),
        _statCard2(recovery),
        const SizedBox(height: 14),
        CalendarCard(
          checkIns: _checkIns,
          startDate: DateTime.parse(challenge.startDate),
          endDate: DateTime.parse(challenge.endDate),
        ),
        const SizedBox(height: 14),
        _endButton(),
      ],
    );
  }

  // 이번 주 성공일 / 주간 목표 인증 횟수 비율. weeklyTarget은 생성 직후에만
  // 채워지는 클라이언트 전용 값이라(§Challenge.weeklyTarget 주석 참고),
  // 서버에서 다시 조회한 챌린지는 기본값(주 3회, 생성 화면 기본 선택값과 동일)을 쓴다.
  double _weeklyGoalPct(Challenge challenge) {
    final target = challenge.weeklyTarget ?? 3;
    if (target <= 0) return 0;
    return (_weekSuccessCount / target).clamp(0, 1).toDouble();
  }

  String _deadlineText(Challenge challenge) {
    final parts = (challenge.deadlineTime ?? '23:00').split(':');
    final hour = int.tryParse(parts[0]) ?? 23;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final now = DateTime.now();
    final deadline = DateTime(now.year, now.month, now.day, hour, minute);
    final remaining = deadline.difference(now);
    if (remaining.isNegative) return '오늘 인증이 마감되었어요';
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return h > 0 ? '오늘 인증 마감까지 $h시간 $m분' : '오늘 인증 마감까지 $m분';
  }

  Widget _hero(bool recovery, Challenge challenge) {
    final grad = recovery
        ? const LinearGradient(
            begin: Alignment(-0.6, -1),
            end: Alignment(0.8, 1),
            colors: [Color(0xFF4E9BFF), Color(0xFF1F6FEB)])
        : BC.heroGrad;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: (recovery ? BC.blue : BC.o2).withOpacity(.32),
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
                color: Colors.white.withOpacity(.22),
                borderRadius: BorderRadius.circular(999)),
            child: Text(recovery ? '복귀 모드' : '현재 챌린지',
                style: const TextStyle(
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
                          child: Text(challenge.title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // TODO: 코인/보상 시스템이 API 스펙에 아직 없어 0으로 표시.
                    const Text('이번 챌린지에서 모은 코인',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        CoinDot(size: 24),
                        SizedBox(width: 8),
                        Text('0',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800)),
                        SizedBox(width: 6),
                        Padding(
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
                          color: Colors.white.withOpacity(.18),
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(_deadlineText(challenge),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ring(_weeklyGoalPct(challenge), recovery),
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
                children: [
                  Icon(recovery ? Icons.refresh_rounded : Icons.calendar_today_rounded,
                      color: recovery ? BC.blue : BC.oMain, size: 18),
                  const SizedBox(width: 8),
                  Text(recovery ? '복귀 미션 하러 가기' : '오늘 인증하러 가기',
                      style: TextStyle(
                          color: recovery ? BC.blue : BC.oMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      color: recovery ? BC.blue : BC.oMain, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double pct, bool recovery) {
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
              const Text('주간 목표',
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

  Widget _statCard1(bool recovery) {
    return AppCard(
      child: Row(
        children: [
          _stat(
            icon: Icons.local_fire_department_rounded,
            iconColor: recovery ? BC.blue : BC.oMain,
            iconBg: recovery ? BC.blueSoft : BC.oSoft,
            label: '연속 인증',
            value: '$_currentStreak',
            unit: '일',
            valueColor: recovery ? BC.blue : BC.oMain,
            tag: '최고 기록 $_bestStreak일',
          ),
          _divider(),
          _stat(
            icon: Icons.event_available_rounded,
            iconColor: BC.green,
            iconBg: BC.greenSoft,
            label: '이번 주 성공일',
            value: '$_weekSuccessCount',
            unit: '일',
            valueColor: BC.green,
            tag: '이번 주 인증 기록',
            tagHi: true,
          ),
        ],
      ),
    );
  }

  Widget _statCard2(bool recovery) {
    // "7일 연속 인증 → +100 코인"은 빈 상태 화면(_infoCard)에도 표시되는
    // 고정 보상 규칙이라 여기서도 같은 값을 쓴다. 코인 지급 자체는 API가
    // 없어 실행되지 않지만, 이 규칙과 남은 일수는 실제 연속 인증 데이터로
    // 계산한 값이다.
    const milestoneDays = 7;
    final positionInCycle = _currentStreak % milestoneDays;
    final daysToNextReward = milestoneDays - positionInCycle;
    final progress = positionInCycle / milestoneDays;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stat(
            icon: Icons.emoji_events_rounded,
            iconColor: recovery ? BC.blue : BC.oMain,
            iconBg: recovery ? BC.blueSoft : BC.oSoft,
            label: '누적 성공 인증',
            value: '$_totalSuccessCount',
            unit: '회',
            valueColor: BC.ink,
            tag: '챌린지 진행 중',
          ),
          _divider(),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: recovery ? BC.blueSoft : BC.oSoft,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.star_rounded,
                      size: 24, color: recovery ? BC.blue : BC.oMain),
                ),
                const SizedBox(height: 6),
                const Text('다음 보상', style: TextStyle(fontSize: 12.5, color: BC.ink2)),
                Text('+100',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: recovery ? BC.blue : BC.oMain)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: BC.line,
                    valueColor: AlwaysStoppedAnimation(recovery ? BC.blue : BC.oMain),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('7일 연속 인증',
                        style: TextStyle(fontSize: 11, color: BC.ink3)),
                    Text('$daysToNextReward일 남음',
                        style: TextStyle(
                            fontSize: 11,
                            color: recovery ? BC.blue : BC.oMain,
                            fontWeight: FontWeight.w700)),
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

  Widget _divider() =>
      Container(width: 1, height: 96, color: BC.line, margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _endButton() {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: BC.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.flag_rounded, size: 17, color: Color(0xFFC2C2C8)),
          SizedBox(width: 7),
          Text('챌린지 종료하기',
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFFC2C2C8))),
        ],
      ),
    );
  }

  // ───────────────────────── 생성 전(빈 상태) ─────────────────────────
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
                  Icon(Icons.add_rounded, size: 34, color: BC.oMain),
                  SizedBox(height: 8),
                  Text('챌린지를 생성하세요',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: BC.oMain)),
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
            Text('챌린지 시작 전 알아두기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: BC.oMain)),
          ],
        ),
        const SizedBox(height: 12),
        _infoCard(Icons.local_fire_department_rounded, BC.oSoft, BC.oMain, '7일 연속 인증',
            '+100 코인', '7일 연속 인증에 성공하면 보상을 받아요!'),
        const SizedBox(height: 10),
        _infoCard(Icons.close_rounded, BC.oMain, Colors.white, '하루 실패', '-100 코인',
            '면제일이 모두 소진된 상태에서 하루를 놓치면 코인이 차감돼요.',
            solid: true),
        const SizedBox(height: 10),
        _infoCard(Icons.refresh_rounded, BC.oSoft, BC.oMain, '복귀 미션 수행', '+50 코인',
            '복귀 미션을 완료하면 코인을 받을 수 있어요!'),
        const SizedBox(height: 20),
        PrimaryButton(
          label: '챌린지 만들기',
          trailingIcon: Icons.chevron_right_rounded,
          onTap: () async {
            final created = await Navigator.of(context).push<Challenge>(
                MaterialPageRoute(builder: (_) => const PersonalCreateScreen()));
            // 생성 API 응답(POST 결과)을 그대로 반영한다 — 별도 전체 재조회 없이
            // 방금 만든 챌린지가 바로 홈 화면에 보인다.
            if (created != null && mounted) _onChallengeCreated(created);
          },
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, Color iconBg, Color iconColor, String title, String amt,
      String desc,
      {bool solid = false}) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: solid ? BC.oMain : iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 23, color: solid ? Colors.white : iconColor),
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
      ..color = Colors.white.withOpacity(.28)
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
class CalendarCard extends StatefulWidget {
  final List<CheckIn> checkIns;
  final DateTime startDate;
  final DateTime endDate;
  const CalendarCard({
    super.key,
    required this.checkIns,
    required this.startDate,
    required this.endDate,
  });
  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  late final List<DateTime> _months;
  late int _i;

  @override
  void initState() {
    super.initState();
    _months = _monthsBetween(widget.startDate, widget.endDate);
    final now = DateTime.now();
    final currentIdx = _months.indexWhere((m) => m.year == now.year && m.month == now.month);
    _i = currentIdx >= 0 ? currentIdx : _months.length - 1;
  }

  static List<DateTime> _monthsBetween(DateTime start, DateTime end) {
    final months = <DateTime>[];
    var cur = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    while (!cur.isAfter(last)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    return months.isEmpty ? [DateTime(start.year, start.month)] : months;
  }

  @override
  Widget build(BuildContext context) {
    final month = _months[_i];
    final year = month.year, m = month.month;
    final first = DateTime(year, m, 1).weekday % 7; // 일=0
    final days = DateTime(year, m + 1, 0).day;

    final done = <int>{};
    final rec = <int>{};
    for (final c in widget.checkIns) {
      final d = c.date;
      if (d.year != year || d.month != m) continue;
      if (c.isRecovery) {
        rec.add(d.day);
      } else if (c.isSuccess) {
        done.add(d.day);
      }
    }

    final cells = <Widget>[];
    for (int k = 0; k < first; k++) cells.add(const SizedBox());
    for (int d = 1; d <= days; d++) {
      Color? bg;
      Color fg = BC.ink2;
      if (rec.contains(d)) {
        bg = BC.blue;
        fg = Colors.white;
      } else if (done.contains(d)) {
        bg = BC.green;
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _arrow(Icons.chevron_left_rounded, _i > 0, () => setState(() => _i--)),
              SizedBox(
                width: 90,
                child: Text('$m월 기록',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              _arrow(Icons.chevron_right_rounded, _i < _months.length - 1,
                  () => setState(() => _i++)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: ['일', '월', '화', '수', '목', '금', '토']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: d == '일' ? const Color(0xFFE5484D) : BC.ink3)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            childAspectRatio: 1,
            children: cells,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _legend(BC.green, '인증 완료'),
              _legend(BC.blue, '복귀 인증'),
              _legend(const Color(0xFFECECEE), '인증 미완료'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: Icon(icon, size: 22, color: BC.ink2),
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: BC.ink2)),
      ],
    );
  }
}
