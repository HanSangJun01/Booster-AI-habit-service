import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});
  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  bool notif = true;
  bool recoveryNotif = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // header (title + bell)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Row(
                children: [
                  const Text('마이페이지',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const NotificationBell(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _profileCard(),
                  const SizedBox(height: 22),
                  _section('내 활동', [
                    _row(Icons.receipt_long_rounded, BC.oMain, BC.oSoft, '코인 내역',
                        sub: '적립·차감 내역 보기', value: '12,450'),
                    _row(Icons.groups_rounded, BC.blue, BC.blueSoft, '참여 중인 팀', badge: '2'),
                    _row(Icons.verified_rounded, BC.green, BC.greenSoft, '인증 기록'),
                  ]),
                  const SizedBox(height: 18),
                  _section('설정', [
                    _row(Icons.edit_rounded, BC.oMain, BC.oSoft, '프로필 수정',
                        sub: '닉네임·프로필 이미지'),
                    _switchRow(Icons.notifications_rounded, '알림 수신', notif,
                        (v) => setState(() => notif = v)),
                    _switchRow(Icons.refresh_rounded, '복귀 미션 알림', recoveryNotif,
                        (v) => setState(() => recoveryNotif = v)),
                    _row(Icons.schedule_rounded, BC.ink3, const Color(0xFFF1F2F5), '알림 시간',
                        value: '오후 9:00'),
                  ]),
                  const SizedBox(height: 18),
                  _section('계정', [
                    _row(Icons.logout_rounded, BC.ink3, const Color(0xFFF1F2F5), '로그아웃'),
                    _row(Icons.person_off_rounded, const Color(0xFFE5484D),
                        const Color(0xFFFDEAEA), '회원 탈퇴', danger: true),
                  ]),
                  const SizedBox(height: 22),
                  Center(
                    child: Column(
                      children: [
                        Text.rich(TextSpan(children: [
                          _link('이용약관'),
                          const TextSpan(text: '   ·   ', style: TextStyle(color: BC.ink3)),
                          _link('개인정보처리방침'),
                        ])),
                        const SizedBox(height: 8),
                        const Text('Booster v1.0.0',
                            style: TextStyle(fontSize: 12, color: BC.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  TextSpan _link(String t) =>
      TextSpan(text: t, style: const TextStyle(fontSize: 12.5, color: BC.ink2));

  Widget _profileCard() {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.person_rounded, size: 32, color: BC.oMain),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          gradient: BC.grad,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.edit_rounded, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('김민준', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('minjun@example.com',
                      style: TextStyle(fontSize: 13, color: BC.ink3)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration:
                BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const CoinDot(size: 22),
                const SizedBox(width: 9),
                const Text('보유 코인',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: BC.ink2)),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: const [
                    Text('12,450',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800, color: BC.oMain)),
                    SizedBox(width: 3),
                    Text('코인',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: BC.ink2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: BC.ink2)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: BC.line),
                rows[i],
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, Color fg, Color bg, String label,
      {String? sub, String? value, String? badge, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: danger ? const Color(0xFFE5484D) : BC.ink)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub, style: const TextStyle(fontSize: 12, color: BC.ink3)),
                  ),
              ],
            ),
          ),
          if (value != null)
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: BC.ink2)),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration:
                  BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(badge,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: BC.oMain)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, size: 20, color: BC.ink3),
        ],
      ),
    );
  }

  Widget _switchRow(IconData icon, String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xFFF1F2F5), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 20, color: BC.ink3),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: BC.oMain,
          ),
        ],
      ),
    );
  }
}
