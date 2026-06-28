import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  bool personalDone = false;

  Future<void> _startGpsVerify() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => const _GpsVerifySheet(),
    );
    if (ok == true && mounted) {
      setState(() => personalDone = true);
      showBoosterToast(context, '오늘 인증을 완료했어요! 🔥');
    }
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  const Text('오늘의 인증',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('참여 중인 챌린지에서 인증을 완료해 보세요.',
                      style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                  const SizedBox(height: 22),
                  _sectionTitle(Icons.person_rounded, BC.oMain, BC.oSoft, '개인 챌린지', '1'),
                  const SizedBox(height: 12),
                  _personalCard(),
                  const SizedBox(height: 24),
                  _sectionTitle(Icons.groups_rounded, BC.blue, BC.blueSoft, '팀 챌린지', '2'),
                  const SizedBox(height: 12),
                  _teamCard('다 같이 헬스', 53, 47, 'Team Blue', BC.blue, '🔥 우리 팀이 6%p 앞서고 있어요',
                      true, '종료까지 2일'),
                  const SizedBox(height: 12),
                  _teamCard('아침 러닝 챌린지', 48, 52, 'Team Green', BC.green,
                      '상대 팀이 4%p 앞서 있어요', false, '종료까지 5일'),
                ],
              ),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, Color fg, Color bg, String title, String count) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: fg),
        ),
        const SizedBox(width: 9),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(count,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
        ),
      ],
    );
  }

  Widget _personalCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: BC.oMain),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('매일 30분 운동하기',
                                style:
                                    TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          ),
                          _statusPill(personalDone),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                            color: BC.oSoft, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.location_on_rounded, size: 14, color: BC.oMain),
                            SizedBox(width: 4),
                            Text('GPS 위치 인증',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: BC.oMain)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _meta('연속 인증', '12', '일'),
                          Container(
                              width: 1, height: 34, color: BC.line, margin: const EdgeInsets.symmetric(horizontal: 14)),
                          _meta('목표 달성률', '78', '%'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      personalDone
                          ? _doneButton()
                          : PrimaryButton(
                              label: '인증하기',
                              leadingIcon: Icons.location_on_rounded,
                              onTap: _startGpsVerify,
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String label, String val, String unit) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
          child: const Icon(Icons.local_fire_department_rounded, size: 19, color: BC.oMain),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: BC.ink3)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(val,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(unit, style: const TextStyle(fontSize: 12, color: BC.ink2)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusPill(bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: done ? BC.greenSoft : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 14, color: done ? BC.green : BC.ink3),
          const SizedBox(width: 5),
          Text(done ? '오늘 인증 완료' : '오늘 인증 미완료',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: done ? BC.green : BC.ink3)),
        ],
      ),
    );
  }

  Widget _doneButton() {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: BC.greenSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_rounded, color: BC.green, size: 20),
          SizedBox(width: 8),
          Text('인증 완료',
              style: TextStyle(color: BC.green, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _teamCard(String name, int ours, int theirs, String oppName, Color oppColor,
      String lead, bool leading, String endsIn) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              _statusPill(false),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _teamSide('우리 팀', 'Team Orange', '$ours%', BC.oMain,
                  Icons.local_fire_department_rounded, true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('VS',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: BC.ink3)),
              ),
              _teamSide('상대 팀', oppName, '$theirs%', oppColor,
                  Icons.water_drop_rounded, false),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(flex: ours, child: Container(height: 10, color: BC.oMain)),
                Expanded(flex: theirs, child: Container(height: 10, color: oppColor)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(lead,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: leading ? BC.oMain : oppColor)),
              ),
              Text(endsIn,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: BC.ink3)),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => showBoosterToast(context, '팀 챌린지 인증은 곧 제공될 예정이에요.'),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.location_on_rounded, size: 19, color: BC.oMain),
                  SizedBox(width: 7),
                  Text('인증하기',
                      style: TextStyle(
                          color: BC.oMain, fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamSide(String role, String team, String pct, Color color, IconData icon, bool left) {
    final col = Column(
      crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$role · $team',
            style: const TextStyle(fontSize: 11, color: BC.ink3, fontWeight: FontWeight.w600)),
        Text(pct, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      ],
    );
    final badge = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: color),
    );
    return Expanded(
      child: Row(
        mainAxisAlignment: left ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: left ? [badge, const SizedBox(width: 8), col] : [col, const SizedBox(width: 8), badge],
      ),
    );
  }
}

/// GPS 인증 바텀시트: 탐지 → 매칭 → 성공
class _GpsVerifySheet extends StatefulWidget {
  const _GpsVerifySheet();
  @override
  State<_GpsVerifySheet> createState() => _GpsVerifySheetState();
}

class _GpsVerifySheetState extends State<_GpsVerifySheet> with SingleTickerProviderStateMixin {
  int stage = 0; // 0 탐지, 1 매칭, 2 성공
  late final AnimationController _ctrl;
  Timer? _t1, _t2;

  static const _titles = ['위치를 탐지하고 있어요', '등록한 장소와 맞춰보는 중', '인증 완료!'];
  static const _subs = [
    'GPS 신호를 받아오는 중이에요…',
    '서울 서초구 반포한강공원',
    '오늘의 인증이 기록됐어요',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _t1 = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => stage = 1);
    });
    _t2 = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        _ctrl.stop();
        setState(() => stage = 2);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _t1?.cancel();
    _t2?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 28 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: BC.line, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 30),
          SizedBox(height: 150, child: stage < 2 ? _radar() : _success()),
          const SizedBox(height: 26),
          Text(_titles[stage],
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_subs[stage],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
          const SizedBox(height: 28),
          if (stage == 2)
            PrimaryButton(
                label: '확인', onTap: () => Navigator.of(context).pop(true))
          else
            Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: BC.bg, borderRadius: BorderRadius.circular(16)),
              child: const Text('인증 처리 중…',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink3)),
            ),
        ],
      ),
    );
  }

  Widget _radar() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 3; i++) _ring((_ctrl.value + i / 3) % 1.0),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(gradient: BC.grad, shape: BoxShape.circle),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 30),
            ),
          ],
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = 56 + t * 90;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: BC.oMain.withOpacity((1 - t) * 0.5), width: 2),
      ),
    );
  }

  Widget _success() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (_, v, __) => Transform.scale(
        scale: v,
        child: Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(color: BC.greenSoft, shape: BoxShape.circle),
          child: Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: BC.green, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
            ),
          ),
        ),
      ),
    );
  }
}
