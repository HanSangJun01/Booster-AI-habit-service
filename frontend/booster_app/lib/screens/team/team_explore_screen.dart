import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_detail_screen.dart';

class TeamExploreScreen extends StatelessWidget {
  const TeamExploreScreen({super.key});

  // 공개 팀만 노출 (비공개는 코드로만 참여)
  static const _teams = [
    ('다 같이 헬스', '매일 30분 운동하기!', ['운동', '헬스', '매일 인증'], '8/10'),
    ('아침러닝 챌린지', '건강한 하루의 시작', ['러닝', '아침운동', '습관'], '6/10'),
    ('등산 가즈아', '주말엔 산으로!', ['등산', '아웃도어', '주말'], '7/10'),
    ('플랭크 30일', '코어 단단하게', ['홈트', '코어', '주 5회'], '5/10'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '팀 탐색', trailing: CoinPill()),
            // 검색 + 코드 참여
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BC.line),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.search_rounded, size: 20, color: BC.ink3),
                          SizedBox(width: 8),
                          Text('팀 이름 또는 키워드 검색',
                              style: TextStyle(fontSize: 14, color: BC.ink3)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _showCodeSheet(context),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                          color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: const [
                          Icon(Icons.vpn_key_rounded, size: 18, color: BC.oMain),
                          SizedBox(width: 6),
                          Text('코드 참여',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: BC.oMain)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                children: [
                  for (final t in _teams) _card(context, t.$1, t.$2, t.$3, t.$4),
                  const SizedBox(height: 4),
                  _banner(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String name, String desc, List<String> tags,
      String members) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              TeamDetailScreen(name: name, desc: desc, tags: tags, members: members))),
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
                  Row(children: [
                    const Icon(Icons.people_alt_rounded, size: 16, color: BC.ink3),
                    const SizedBox(width: 5),
                    Text(members,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: BC.ink2)),
                    const Spacer(),
                    const Text('예치코인 500',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4A4E))),
                    const SizedBox(width: 5),
                    const CoinDot(size: 16, symbol: '\$'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: BC.grad, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('우리 팀을 만들어보세요!',
                    style: TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('팀을 만들고 함께 목표를 달성해보세요.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }

  void _showCodeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('방 코드로 참여',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('비공개 팀은 방장이 공유한 코드로만 참여할 수 있어요.',
                style: TextStyle(fontSize: 13.5, color: BC.ink2)),
            const SizedBox(height: 16),
            TextField(
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: '예) 7K2Q',
                filled: true,
                fillColor: BC.bg,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: BC.line, width: 1.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: BC.oMain, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: '참여하기',
              onTap: () {
                Navigator.of(ctx).pop();
                showBoosterToast(context, '코드를 확인하고 있어요…');
              },
            ),
          ],
        ),
      ),
    );
  }
}
