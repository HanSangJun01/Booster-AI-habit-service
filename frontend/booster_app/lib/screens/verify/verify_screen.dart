import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/challenge.dart';
import '../../models/check_in.dart';
import '../../models/team.dart';
import '../../services/challenge_service.dart';
import '../../services/team_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

/// 팀 하나의 인증 카드에 필요한 데이터 묶음. 팀에 진행 중인 챌린지가 아직
/// 없으면(정원 미달 등) challenge가 null이고 checkIns는 비어 있다.
class _TeamChallengeInfo {
  final Team team;
  final Challenge? challenge;
  final List<CheckIn> checkIns;
  _TeamChallengeInfo({required this.team, required this.challenge, required this.checkIns});
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  bool _loading = true;
  Challenge? _challenge;
  List<CheckIn> _checkIns = [];
  List<_TeamChallengeInfo> _teamInfos = [];
  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold는 탭을 IndexedStack으로 유지해서, 인증 탭을 한 번 연 뒤엔
    // 다른 탭(팀 생성 등)에서 상태가 바뀌어도 initState가 다시 안 불린다.
    // 인증 탭(index 2)이 "새로 활성화"될 때마다 다시 불러와서 최신 상태를 본다.
    const verifyTabIndex = 2;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == verifyTabIndex && _lastActiveTabIndex != verifyTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final challenge = await ChallengeService.fetchActiveChallenge();
      final checkIns = challenge == null
          ? <CheckIn>[]
          : await ChallengeService.fetchCheckIns(challenge.challengeId);
      final teams = await TeamService.fetchMyTeams();
      final teamInfos = <_TeamChallengeInfo>[];
      for (final team in teams) {
        final teamChallenge = await ChallengeService.fetchActiveChallengeForTeam(team.teamId);
        final teamCheckIns = teamChallenge == null
            ? <CheckIn>[]
            : await ChallengeService.fetchCheckIns(teamChallenge.challengeId);
        teamInfos.add(_TeamChallengeInfo(
            team: team, challenge: teamChallenge, checkIns: teamCheckIns));
      }
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _checkIns = checkIns;
        _teamInfos = teamInfos;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != null) showBoosterToast(context, e.message);
      setState(() {
        _challenge = null;
        _checkIns = [];
        _teamInfos = [];
        _loading = false;
      });
    }
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  bool get _doneToday => _checkIns.any((c) => c.checkInDate == _today);

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

  int get _totalSuccessCount => _checkIns.where((c) => c.isSuccess).length;

  Future<void> _startGpsVerify() async {
    final challenge = _challenge;
    if (challenge == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => const _GpsVerifySheet(),
    );
    if (ok != true || !mounted) return;

    try {
      final checkIn = await ChallengeService.createCheckIn(challenge.challengeId);
      final passed = await ChallengeService.submitGpsVerification(checkIn.checkInId);
      if (!mounted) return;
      setState(() {
        _checkIns = [
          ..._checkIns,
          CheckIn(
            checkInId: checkIn.checkInId,
            checkInDate: checkIn.checkInDate,
            status: passed ? 'SUCCESS' : 'FAILED',
          ),
        ];
      });
      showBoosterToast(
          context, passed ? '오늘 인증을 완료했어요! 🔥' : '인증 반경을 벗어났어요. 다시 시도해주세요.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    }
  }

  bool _doneTodayFor(List<CheckIn> checkIns) => checkIns.any((c) => c.checkInDate == _today);

  int _currentStreakFor(List<CheckIn> checkIns) {
    final success = checkIns.where((c) => c.isSuccess).map((c) => c.date).toSet();
    var day = DateTime.now();
    var streak = 0;
    while (success.contains(DateTime(day.year, day.month, day.day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _startTeamGpsVerify(_TeamChallengeInfo info) async {
    final challenge = info.challenge;
    if (challenge == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.5),
      builder: (_) => const _GpsVerifySheet(),
    );
    if (ok != true || !mounted) return;

    try {
      final checkIn = await ChallengeService.createCheckIn(challenge.challengeId);
      final passed = await ChallengeService.submitGpsVerification(checkIn.checkInId);
      if (!mounted) return;
      setState(() {
        final idx = _teamInfos.indexWhere((i) => i.team.teamId == info.team.teamId);
        if (idx == -1) return;
        _teamInfos[idx] = _TeamChallengeInfo(
          team: info.team,
          challenge: challenge,
          checkIns: [
            ...info.checkIns,
            CheckIn(
              checkInId: checkIn.checkInId,
              checkInDate: checkIn.checkInDate,
              status: passed ? 'SUCCESS' : 'FAILED',
            ),
          ],
        );
      });
      showBoosterToast(
          context, passed ? '오늘 팀 인증을 완료했어요! 🔥' : '인증 반경을 벗어났어요. 다시 시도해주세요.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      children: [
                        const Text('오늘의 인증',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        const Text('참여 중인 챌린지에서 인증을 완료해 보세요.',
                            style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                        const SizedBox(height: 22),
                        _sectionTitle(Icons.person_rounded, BC.oMain, BC.oSoft, '개인 챌린지',
                            _challenge == null ? '0' : '1'),
                        const SizedBox(height: 12),
                        _challenge == null ? _noPersonalChallenge() : _personalCard(_challenge!),
                        if (_teamInfos.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _sectionTitle(Icons.groups_rounded, BC.blue, BC.blueSoft, '팀 챌린지',
                              '${_teamInfos.length}'),
                          const SizedBox(height: 12),
                          for (final info in _teamInfos) ...[
                            _teamCard(info),
                            const SizedBox(height: 12),
                          ],
                        ],
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

  Widget _noPersonalChallenge() {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.add_circle_outline_rounded, size: 32, color: BC.ink3),
          const SizedBox(height: 8),
          const Text('진행 중인 개인 챌린지가 없어요',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink2)),
          const SizedBox(height: 4),
          const Text('홈 화면에서 챌린지를 먼저 만들어보세요.',
              style: TextStyle(fontSize: 12.5, color: BC.ink3)),
        ],
      ),
    );
  }

  Widget _personalCard(Challenge challenge) {
    final done = _doneToday;
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
                          Expanded(
                            child: Text(challenge.title,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800)),
                          ),
                          _statusPill(done),
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
                          _meta('연속 인증', '$_currentStreak', '일'),
                          Container(
                              width: 1,
                              height: 34,
                              color: BC.line,
                              margin: const EdgeInsets.symmetric(horizontal: 14)),
                          _meta('누적 인증', '$_totalSuccessCount', '회'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      done
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

  // 참여율·상대팀 VS 대결 통계는 배틀/랭킹 관련 API가 없어서 아직 못 채운다.
  // 체크인(인증) 자체는 개인 챌린지와 동일한 API로 실제 연동돼 있다.
  Widget _teamCard(_TeamChallengeInfo info) {
    final team = info.team;
    final challenge = info.challenge;

    if (challenge == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(team.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                MiniTag(team.isFull ? '배틀 진행 중' : '팀원 모집 중',
                    bg: team.isFull ? BC.oSoft : BC.blueSoft,
                    fg: team.isFull ? BC.oMain : BC.blue),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              team.isFull ? '아직 팀 챌린지가 생성되지 않았어요.' : '팀원이 다 모이면 배틀과 함께 인증이 시작돼요.',
              style: const TextStyle(fontSize: 13, color: BC.ink2),
            ),
          ],
        ),
      );
    }

    final done = _doneTodayFor(info.checkIns);
    final streak = _currentStreakFor(info.checkIns);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name,
                        style: const TextStyle(fontSize: 13, color: BC.ink3)),
                    Text(challenge.title,
                        style:
                            const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              _statusPill(done),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded, size: 16, color: BC.blue),
              const SizedBox(width: 5),
              Text('연속 인증 $streak일',
                  style: const TextStyle(fontSize: 12.5, color: BC.ink2, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          done
              ? _doneButton()
              : GestureDetector(
                  onTap: () => _startTeamGpsVerify(info),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: BC.blueSoft, borderRadius: BorderRadius.circular(14)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_rounded, size: 19, color: BC.blue),
                        SizedBox(width: 7),
                        Text('인증하기',
                            style: TextStyle(
                                color: BC.blue, fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
        ],
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
