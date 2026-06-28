import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

class TeamBattleScreen extends StatelessWidget {
  final String teamName;
  const TeamBattleScreen({super.key, this.teamName = 'Team Orange'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '팀 배틀'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                children: [
                  _vsHero(),
                  const SizedBox(height: 14),
                  _leadCard(),
                  const SizedBox(height: 12),
                  _participation(),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _tpCard(Icons.hourglass_bottom_rounded, '종료까지', '2일 14시간',
                            const Color(0xFFF6F5F3), BC.ink2)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _tpCard(Icons.monetization_on_rounded, '우승 상금', '2,420 코인',
                            const Color(0xFFFFF6E0), const Color(0xFFF0A500))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _statCard(true)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard(false)),
                  ]),
                  const SizedBox(height: 12),
                  _rules(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: BC.line)),
              ),
              child: PrimaryButton(
                label: '인증하러 가기',
                leadingIcon: Icons.location_on_rounded,
                onTap: () {
                  // 인증 탭으로 전환 후 팀 네비게이터는 루트로
                  MainNavScope.of(context).select(2);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vsHero() {
    return SizedBox(
      height: 172,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFFFF7A3D), Color(0xFFF0440A)])),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF3D7BFB), Color(0xFF1A52D8)])),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(child: _vsCol(Icons.local_fire_department_rounded, 'Team Orange', '53', BC.oMain)),
              Expanded(child: _vsCol(Icons.water_drop_rounded, 'Team Blue', '47', BC.blue)),
            ],
          ),
          const Center(
            child: Text('VS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _vsCol(IconData icon, String name, String pct, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 27),
        ),
        const SizedBox(height: 6),
        Text(name,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        Text('$pct%',
            style: const TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
        const Text('참여율',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _leadCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: const [
          Text.rich(TextSpan(children: [
            TextSpan(text: '🔥 '),
            TextSpan(
                text: 'Team Orange',
                style: TextStyle(color: BC.oMain, fontWeight: FontWeight.w800)),
            TextSpan(
                text: '가 6%p 앞서는 중!',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]), style: TextStyle(fontSize: 17)),
          SizedBox(height: 5),
          Text('누적 인증 참여율 기준',
              style: TextStyle(fontSize: 12.5, color: BC.ink3, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _participation() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('TEAM ORANGE',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: BC.oMain)),
                  Text('53%',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: BC.oMain)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text('TEAM BLUE',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: BC.blue)),
                  Text('47%',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: BC.blue)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(flex: 53, child: Container(height: 12, color: BC.oMain)),
                Expanded(flex: 47, child: Container(height: 12, color: BC.blue)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tpCard(IconData icon, String label, String value, Color iconBg, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
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
          ),
        ],
      ),
    );
  }

  Widget _statCard(bool ours) {
    final color = ours ? BC.oMain : BC.blue;
    final bg = ours ? BC.oSoft : BC.blueSoft;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ours ? '우리 팀 (Team Orange)' : '상대 팀 (Team Blue)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 12),
          _statRow(Icons.people_alt_rounded, '참여 인원', '5명', color),
          const SizedBox(height: 11),
          _statRow(Icons.check_circle_rounded, '누적 인증', ours ? '47회' : '42회', color),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5, color: BC.ink2, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _rules() {
    Widget li(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: BC.oMain, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.55)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFFF8F7F5), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.fact_check_rounded, size: 19, color: BC.oMain),
            SizedBox(width: 8),
            Text('배틀 규칙',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 11),
          li('참여율 = 팀 누적 인증 ÷ (챌린지 기간 × 팀 인원)'),
          li('종료 시 참여율이 더 높은 팀이 승리해요'),
          li('승리 팀이 전체 예치 코인을 인원수로 나눠 가져요 (동률 시 전원 반환)'),
        ],
      ),
    );
  }
}
