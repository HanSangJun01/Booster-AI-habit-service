import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'team_explore_screen.dart';
import 'team_detail_screen.dart';
import 'team_create_screen.dart';

class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({super.key});
  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  bool hasTeams = true;

  void _goExplore() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const TeamExploreScreen()));
  void _goCreate() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const TeamCreateScreen()));
  void _goDetail(String name, String desc, List<String> tags, String members) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeamDetailScreen(name: name, desc: desc, tags: tags, members: members)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoosterHeader(),
            Expanded(child: hasTeams ? _populated() : _empty()),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _demoToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        const Text('[데모] 상태',
            style: TextStyle(fontSize: 12, color: BC.ink3, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        for (final e in [('내 팀 있음', true), ('팀 없음', false)]) ...[
          GestureDetector(
            onTap: () => setState(() => hasTeams = e.$2),
            child: Container(
              margin: const EdgeInsets.only(right: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: hasTeams == e.$2 ? BC.oMain : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: hasTeams == e.$2 ? BC.oMain : BC.line, width: 1.5),
              ),
              child: Text(e.$1,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasTeams == e.$2 ? Colors.white : BC.ink3)),
            ),
          ),
        ],
      ]),
    );
  }

  // ───────────── 내 팀 있음 ─────────────
  Widget _populated() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _demoToggle(),
        const Text('내 팀', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 13),
        _teamCard('다 같이 헬스', '매일 30분 운동하기!', ['운동', '헬스', '매일 인증'], '8/10'),
        _teamCard('아침러닝 챌린지', '건강한 하루의 시작', ['러닝', '아침운동', '습관'], '6/10'),
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

  Widget _teamCard(String name, String desc, List<String> tags, String members) {
    return GestureDetector(
      onTap: () => _goDetail(name, desc, tags, members),
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
                  Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((t) => MiniTag(t)).toList()),
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

  // ───────────── 팀 없음(빈 상태) ─────────────
  Widget _empty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _demoToggle(),
        const Text('팀에 참여해서 함께\n더 큰 동기부여를 받아보세요!',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, height: 1.35)),
        const SizedBox(height: 8),
        const Text('팀은 한 곳만 참여할 수 있어요.',
            style: TextStyle(fontSize: 14, color: BC.ink3)),
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
