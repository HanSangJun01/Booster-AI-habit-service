import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_battle_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  final String name;
  final String desc;
  final List<String> tags;
  final String members; // "8/10"
  const TeamDetailScreen({
    super.key,
    required this.name,
    required this.desc,
    required this.tags,
    required this.members,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  bool joined = false;

  static const _avatarColors = [
    Color(0xFFFF6A38), Color(0xFFF0997B), Color(0xFFFFB088), Color(0xFFFF8A5B),
    Color(0xFFE8723E), Color(0xFFFFA06E), Color(0xFFF08050), Color(0xFFFF7A45),
  ];
  static const _names = ['김', '이', '박', '최', '정', '강', '윤', '한'];

  @override
  Widget build(BuildContext context) {
    final parts = widget.members.split('/');
    final cur = int.tryParse(parts.first) ?? 8;
    final cap = int.tryParse(parts.last) ?? 10;

    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(
              title: '팀 상세',
              trailing: const CoinPill(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                children: [
                  Container(
                    height: 170,
                    decoration: BoxDecoration(
                        gradient: BC.grad, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.image_rounded, color: Colors.white70, size: 44),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Flexible(
                      child: Text(widget.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                    ),
                    const SizedBox(width: 9),
                    const MiniTag('공개', bg: BC.oSoft, fg: BC.oMain),
                  ]),
                  const SizedBox(height: 8),
                  Text(widget.desc,
                      style: const TextStyle(
                          fontSize: 15, color: BC.ink2, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.tags.map((t) => MiniTag(t)).toList()),

                  // 모집 현황
                  _secTitle('모집 현황'),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '$cur',
                                  style: const TextStyle(
                                      color: BC.oMain,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              TextSpan(
                                  text: ' / $cap명',
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700)),
                            ])),
                            const Spacer(),
                            Text('${cap - cur}명 모이면 배틀 시작',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: BC.ink2,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: cur / cap,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE8E6E2),
                            valueColor: const AlwaysStoppedAnimation(BC.oMain),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (int i = 0; i < cap; i++)
                              i < cur
                                  ? Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                          color: _avatarColors[i % _avatarColors.length],
                                          shape: BoxShape.circle),
                                      child: Text(_names[i % _names.length],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    )
                                  : Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: const Color(0xFFD6D4CF),
                                              width: 1.5)),
                                      child: const Icon(Icons.add_rounded,
                                          size: 15, color: Color(0xFFC2C0BB)),
                                    ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 챌린지 정보
                  _secTitle('챌린지 정보'),
                  Row(children: [
                    Expanded(child: _infoCard(Icons.calendar_today_rounded, '기간', '30일')),
                    const SizedBox(width: 10),
                    Expanded(child: _infoCard(Icons.location_on_rounded, '인증 방법', 'GPS')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _infoCard(Icons.repeat_rounded, '인증 주기', '매일')),
                    const SizedBox(width: 10),
                    Expanded(child: _infoCard(Icons.schedule_rounded, '마감 시간', '23:00')),
                  ]),

                  // 대결 방식
                  _secTitle('팀 대결 방식'),
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: BC.line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        _ruleRow(Icons.groups_rounded, '5:5 팀 배틀',
                            '인원이 모이면 두 팀으로 나뉘어 챌린지가 시작돼요.', false),
                        const Divider(height: 1, color: BC.line),
                        _ruleRow(Icons.bar_chart_rounded, '참여율로 승부',
                            '기간 동안 팀 누적 인증 참여율이 더 높은 팀이 이겨요.', false),
                        const Divider(height: 1, color: BC.line),
                        _ruleRow(Icons.emoji_events_rounded, '승리 보상',
                            '이긴 팀이 전체 예치 코인을 나눠 갖고 진 팀은 소멸돼요. 비기면 전원 반환!', true),
                      ],
                    ),
                  ),

                  // 예치코인
                  _secTitle('예치코인'),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: BC.oSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFBD9C7)),
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          const CoinDot(size: 28, symbol: '\$'),
                          const SizedBox(width: 9),
                          const Text('참여 시 차감돼요',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: BC.o2)),
                          const Spacer(),
                          const Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '500',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: BC.oMain)),
                            TextSpan(
                                text: '코인',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: BC.oMain)),
                          ])),
                        ]),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(height: 1, color: Color(0xFFFBDDCD)),
                        ),
                        Row(children: const [
                          Icon(Icons.verified_user_rounded, size: 18, color: BC.oMain),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text('이기면 예치코인을 돌려받고 상금까지 받아요. 비기면 전원 반환돼요',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: BC.ink2,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 참여 CTA
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: BC.line)),
              ),
              child: joined
                  ? Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: const Color(0xFFD4D2CD),
                          borderRadius: BorderRadius.circular(16)),
                      child: const Text('참여 완료',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                    )
                  : PrimaryButton(
                      label: '500코인 걸고 참여하기',
                      leadingIcon: Icons.monetization_on_rounded,
                      onTap: () {
                        setState(() => joined = true);
                        showBoosterToast(context, '참여 완료! 배틀이 곧 시작돼요.');
                        Future.delayed(const Duration(milliseconds: 700), () {
                          if (mounted) {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => TeamBattleScreen(teamName: widget.name)));
                          }
                        });
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFFF8F7F5), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration:
                BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: BC.oMain),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: BC.ink2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ruleRow(IconData icon, String title, String desc, bool last) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                const BoxDecoration(color: Color(0xFFFFEDE4), shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: BC.oMain),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
