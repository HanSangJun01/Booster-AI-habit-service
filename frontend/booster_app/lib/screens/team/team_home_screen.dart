import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../services/challenge_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'team_battle_screen.dart';
import 'team_create_screen.dart';
import 'team_explore_screen.dart';
import 'team_waiting_screen.dart';

/// 팀 탭 홈.
///
/// 백엔드 모델에서 "팀"은 챌린지 안에서 서버가 편성하는 하위 개념이라, 사용자가
/// 다루는 단위는 **챌린지**다. 그래서 이 화면은 내 챌린지를 보여준다.
///
/// 한계: 백엔드에 "내가 참여 중인 챌린지 목록" 엔드포인트가 없다
/// (`GET /api/challenges`는 공개 챌린지 검색이다). 그래서 이번 세션에서
/// 만들었거나 참가한 챌린지 하나만 [Session.currentChallengeId]로 추적하고,
/// 앱을 재시작하면 초대 코드나 탐색으로 다시 찾아 들어가야 한다.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({super.key});
  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  bool _loading = true;
  Challenge? _challenge;
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
    // MainScaffold는 탭을 IndexedStack으로 유지해서 initState가 다시 안 불린다.
    // 팀 탭(index 1)이 새로 활성화될 때마다 최신 상태를 다시 읽는다.
    const teamTabIndex = 1;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == teamTabIndex && _lastActiveTabIndex != teamTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final challengeId = Session.currentChallengeId;
    if (challengeId == null) {
      if (!mounted) return;
      setState(() {
        _challenge = null;
        _loading = false;
      });
      return;
    }
    try {
      final challenge = await ChallengeService.fetchDetail(challengeId);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _challenge = null);
    } finally {
      // 어떤 예외로 빠져나가든 스피너는 반드시 걷는다.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goExplore() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TeamExploreScreen()));
    if (mounted) _load();
  }

  Future<void> _goCreate() async {
    final created = await Navigator.of(context)
        .push<Challenge>(MaterialPageRoute(builder: (_) => const TeamCreateScreen()));
    if (!mounted) return;
    if (created != null) Session.currentChallengeId = created.id;
    _load();
  }

  Future<void> _goChallenge(Challenge challenge) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => challenge.isActive
          ? TeamBattleScreen(challenge: challenge)
          : TeamWaitingScreen(challenge: challenge),
    ));
    if (mounted) _load();
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
                  : (_challenge == null ? _empty() : _populated(_challenge!)),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────── 내 챌린지 있음 ─────────────
  Widget _populated(Challenge challenge) {
    return RefreshIndicator(
      onRefresh: _load,
      color: BC.oMain,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        children: [
          const Text('내 챌린지',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 13),
          _challengeCard(challenge, onTap: () => _goChallenge(challenge)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _actionBox(Icons.search_rounded, '챌린지 탐색', _goExplore)),
              const SizedBox(width: 12),
              Expanded(child: _actionBox(Icons.add_rounded, '챌린지 만들기', _goCreate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBox(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        decoration: BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: BC.oMain, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Text(label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _challengeCard(Challenge challenge, {required VoidCallback onTap}) {
    final statusTag = challenge.isActive
        ? '배틀 진행 중'
        : (challenge.isReady ? '팀원 모집 중' : '종료됨');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BC.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration:
                  BoxDecoration(gradient: BC.grad, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.flag_rounded, color: Colors.white70, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(challenge.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    MiniTag(challenge.isPrivate ? '비공개' : '공개',
                        bg: BC.oSoft, fg: BC.oMain),
                  ]),
                  const SizedBox(height: 5),
                  Text(challenge.description ?? challenge.category,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
                  const SizedBox(height: 9),
                  MiniTag(statusTag,
                      bg: challenge.isActive ? BC.oSoft : BC.blueSoft,
                      fg: challenge.isActive ? BC.oMain : BC.blue),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 16, color: BC.ink3),
                      const SizedBox(width: 5),
                      Text(
                          '${challenge.confirmedCount ?? 0}/${challenge.maxParticipants}',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: BC.ink2)),
                      const Spacer(),
                      Text('예치코인 ${CoinPill.format(challenge.depositCoins)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4A4A4E))),
                      const SizedBox(width: 5),
                      const CoinDot(size: 16, symbol: '\$'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── 챌린지 없음(빈 상태) ─────────────
  Widget _empty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        const Text('팀 챌린지에 참여해서 함께\n더 큰 동기부여를 받아보세요!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.35)),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 170,
            height: 150,
            decoration:
                const BoxDecoration(color: Color(0xFFFDE6DB), shape: BoxShape.circle),
            child: const Icon(Icons.flag_rounded, size: 56, color: BC.oMain),
          ),
        ),
        const SizedBox(height: 24),
        _bigAction(Icons.search_rounded, '챌린지 탐색하기',
            '공개 챌린지를 둘러보거나\n초대 코드로 참여해보세요', _goExplore),
        const SizedBox(height: 14),
        _bigAction(Icons.add_rounded, '챌린지 만들기', '직접 챌린지를 만들고\n팀원들을 모집해보세요',
            _goCreate),
        const SizedBox(height: 18),
        NoteBox(
          icon: Icons.verified_user_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('참여 안내',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('참여하면 챌린지에 걸린 예치 코인이 차감돼요. 팀이 이기면 정산에서 돌려받아요.',
                  style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bigAction(IconData icon, String title, String desc, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(color: BC.oMain, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BC.ink3),
          ],
        ),
      ),
    );
  }
}
