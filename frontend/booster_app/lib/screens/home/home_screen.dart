import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'personal_create_screen.dart';

enum HomeMode { active, recovery, empty }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeMode mode = HomeMode.active;

  Color get accent => mode == HomeMode.recovery ? BC.blue : BC.oMain;

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
              child: mode == HomeMode.empty ? _emptyBody() : _activeBody(),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 상태 전환(데모용) ─────────────────────────
  Widget _modeSwitch() {
    Widget chip(String label, HomeMode m) {
      final on = mode == m;
      return GestureDetector(
        onTap: () => setState(() => mode = m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? accent : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? accent : BC.line, width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : BC.ink3)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        const Text('[데모] 상태',
            style: TextStyle(fontSize: 12, color: BC.ink3, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        chip('진행 중', HomeMode.active),
        const SizedBox(width: 7),
        chip('복귀', HomeMode.recovery),
        const SizedBox(width: 7),
        chip('생성 전', HomeMode.empty),
      ]),
    );
  }

  // ───────────────────────── 진행 중 / 복귀 ─────────────────────────
  Widget _activeBody() {
    final recovery = mode == HomeMode.recovery;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _modeSwitch(),
        _hero(recovery),
        const SizedBox(height: 14),
        _statCard1(recovery),
        const SizedBox(height: 14),
        _statCard2(recovery),
        const SizedBox(height: 14),
        const CalendarCard(),
        const SizedBox(height: 14),
        _endButton(),
      ],
    );
  }

  Widget _hero(bool recovery) {
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
                      children: const [
                        Flexible(
                          child: Text('매일 30분 운동하기',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4)),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('이번 챌린지에서 모은 코인',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        CoinDot(size: 24),
                        SizedBox(width: 8),
                        Text('+1,200',
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
                          Text(recovery ? '복귀 미션 마감까지 5시간' : '오늘 인증 마감까지 5시간',
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
              _ring(0.6, recovery),
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
              const Text('진행률',
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
            value: recovery ? '0' : '12',
            unit: '일',
            valueColor: recovery ? BC.blue : BC.oMain,
            tag: '최고 기록 24일',
          ),
          _divider(),
          _stat(
            icon: Icons.event_available_rounded,
            iconColor: BC.green,
            iconBg: BC.greenSoft,
            label: '이번 주 성공일',
            value: recovery ? '1' : '4',
            unit: '일',
            valueColor: BC.green,
            tag: recovery ? '다시 시작!' : '주 3회 목표 달성!',
            tagHi: true,
          ),
        ],
      ),
    );
  }

  Widget _statCard2(bool recovery) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stat(
            icon: Icons.emoji_events_rounded,
            iconColor: recovery ? BC.blue : BC.oMain,
            iconBg: recovery ? BC.blueSoft : BC.oSoft,
            label: '누적 성공 인증',
            value: '48',
            unit: '회',
            valueColor: BC.ink,
            tag: '코인으로 차곡차곡',
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
                Text(recovery ? '+50' : '+100',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: recovery ? BC.blue : BC.oMain)),
                if (!recovery) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: 0.71,
                      minHeight: 7,
                      backgroundColor: BC.line,
                      valueColor: const AlwaysStoppedAnimation(BC.oMain),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('7일 연속 인증',
                          style: TextStyle(fontSize: 11, color: BC.ink3)),
                      Text('2일 남음',
                          style: TextStyle(
                              fontSize: 11,
                              color: BC.oMain,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ] else
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: BC.blueSoft, borderRadius: BorderRadius.circular(999)),
                    child: const Text('복귀 미션 수행 시',
                        style: TextStyle(
                            fontSize: 11, color: BC.blue, fontWeight: FontWeight.w600)),
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
        _modeSwitch(),
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
            final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const PersonalCreateScreen()));
            if (created == true && mounted) setState(() => mode = HomeMode.active);
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
  const CalendarCard({super.key});
  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  // 표시 대상: 4월, 5월, 6월 (2026)
  static const _year = 2026;
  static const _months = [4, 5, 6];
  int _i = 1; // 5월부터

  static const _done = {
    4: [2, 3, 5, 8, 9, 24, 26, 29, 30],
    5: [1, 2, 3, 5, 6, 7, 9, 12, 16, 22, 24, 27],
    6: <int>[],
  };
  static const _recover = {
    4: [13, 14, 15, 16, 18, 19, 20, 21],
    5: <int>[],
    6: <int>[],
  };

  @override
  Widget build(BuildContext context) {
    final m = _months[_i];
    final first = DateTime(_year, m, 1).weekday % 7; // 일=0
    final days = DateTime(_year, m + 1, 0).day;
    final done = _done[m]!;
    final rec = _recover[m]!;

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
