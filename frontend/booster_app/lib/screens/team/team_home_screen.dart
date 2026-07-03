import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/team.dart';
import '../../services/team_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'team_explore_screen.dart';
import 'team_create_screen.dart';
import 'team_waiting_screen.dart';
import 'team_battle_screen.dart';

class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({super.key});
  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  bool _loading = true;
  List<Team> _myTeams = [];
  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold는 탭을 IndexedStack으로 유지해서, 다른 탭에서 상태가
    // 바뀌어도 이 화면의 initState가 다시 안 불린다. 팀 탭(index 1)이
    // "새로 활성화"될 때마다 다시 불러와서 최신 상태를 본다.
    const teamTabIndex = 1;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == teamTabIndex && _lastActiveTabIndex != teamTabIndex) {
      _loadTeam();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _loadTeam() async {
    setState(() => _loading = true);
    try {
      final teams = await TeamService.fetchMyTeams();
      if (!mounted) return;
      setState(() {
        _myTeams = teams;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // TeamService.fetchMyTeams()는 서버 연결 실패만 내부에서 흡수하고, 실제
      // 에러(statusCode 있음)는 여기까지 그대로 올라온다 — 조용히 감추지 않고
      // 토스트로 드러낸다.
      if (e.statusCode != null) showBoosterToast(context, e.message);
      setState(() {
        _myTeams = [];
        _loading = false;
      });
    }
  }

  void _goExplore() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TeamExploreScreen()));
    if (mounted) _loadTeam();
  }

  void _goCreate() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TeamCreateScreen()));
    if (mounted) _loadTeam();
  }

  void _goTeam(Team team) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => team.isFull
          ? TeamBattleScreen(teamName: team.name)
          : TeamWaitingScreen(team: team),
    ));
    // 대기 화면에서 팀원 승인/강퇴 등으로 인원수가 바뀌었을 수 있어, 돌아오면
    // 다시 조회해서 카드에 최신 인원수를 반영한다.
    if (mounted) _loadTeam();
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
                  : (_myTeams.isEmpty ? _empty() : _populated(_myTeams)),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  // ───────────── 내 팀 있음 ─────────────
  // 사용자는 여러 팀에 동시에 참여할 수 있다(docs/erd/MVP_ERD.md 참고) —
  // 팀이 있어도 새 팀을 탐색/생성할 수 있도록 액션은 항상 보여준다.
  Widget _populated(List<Team> teams) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        const Text('내 팀', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 13),
        for (final team in teams)
          _teamCard(
            team.name,
            team.description ?? '',
            team.isFull ? '배틀 진행 중' : '팀원 모집 중',
            '${team.memberCount}/${team.capacity ?? 10}',
            onTap: () => _goTeam(team),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _actionBox(Icons.search_rounded, '팀 탐색하기', _goExplore)),
            const SizedBox(width: 12),
            Expanded(child: _actionBox(Icons.add_rounded, '팀 만들기', _goCreate)),
          ],
        ),
      ],
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
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(String name, String desc, String statusTag, String members,
      {required VoidCallback onTap}) {
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
              decoration: BoxDecoration(
                  gradient: BC.grad, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.image_rounded, color: Colors.white70, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          style:
                              const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    const MiniTag('공개', bg: BC.oSoft, fg: BC.oMain),
                  ]),
                  const SizedBox(height: 5),
                  Text(desc, style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
                  const SizedBox(height: 9),
                  MiniTag(statusTag,
                      bg: statusTag == '배틀 진행 중' ? BC.oSoft : BC.blueSoft,
                      fg: statusTag == '배틀 진행 중' ? BC.oMain : BC.blue),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 16, color: BC.ink3),
                      const SizedBox(width: 5),
                      Text(members,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: BC.ink2)),
                      const Spacer(),
                      const Text('예치코인 500',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4A4E))),
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

  // ───────────── 팀 없음(빈 상태) ─────────────
  Widget _empty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        const Text('팀에 참여해서 함께\n더 큰 동기부여를 받아보세요!',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, height: 1.35)),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 170,
            height: 150,
            decoration: const BoxDecoration(color: Color(0xFFFDE6DB), shape: BoxShape.circle),
            child: const Icon(Icons.flag_rounded, size: 56, color: BC.oMain),
          ),
        ),
        const SizedBox(height: 24),
        _bigAction(Icons.search_rounded, '팀 탐색하기', '다른 사람들이 만든 팀을\n확인하고 참여해보세요', _goExplore),
        const SizedBox(height: 14),
        _bigAction(Icons.add_rounded, '팀 만들기', '직접 팀을 만들고\n팀원들을 모집해보세요', _goCreate),
        const SizedBox(height: 18),
        NoteBox(
          icon: Icons.verified_user_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('팀 참여 안내',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('팀에 참여하려면 팀장이 설정한 베팅 코인을 지불해야 해요. 베팅 코인은 챌린지 성공 시 돌려받을 수 있어요.',
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
