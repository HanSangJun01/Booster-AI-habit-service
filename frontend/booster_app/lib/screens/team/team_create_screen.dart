import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({super.key});
  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  int step = 0; // 0 기본, 1 공개설정
  int size = 2; // 3:3 / 4:4 / 5:5
  int freq = 2; // 주 N회 (3회)
  int deposit = 1; // 100/300/500
  bool isPublic = true;

  final _sizes = ['3 : 3', '4 : 4', '5 : 5'];
  final _freqs = ['1회', '2회', '3회', '4회', '5회', '6회', '7회'];
  final _deposits = ['100', '300', '500'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(
              title: step == 0 ? '팀 만들기' : '공개 설정',
              trailing: const CoinPill(),
            ),
            _stepDots(),
            Expanded(child: step == 0 ? _basic() : _visibility()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: step == 0
                  ? PrimaryButton(
                      label: '다음',
                      trailingIcon: Icons.chevron_right_rounded,
                      onTap: () => setState(() => step = 1))
                  : PrimaryButton(
                      label: isPublic ? '팀 만들기' : '방 코드 생성하기',
                      onTap: _onCreate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              width: i == step ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                  color: i <= step ? BC.oMain : BC.line,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, {String? sub, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(fontSize: 13, color: BC.ink2)),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chipRow(List<String> items, int sel, ValueChanged<int> onTap) {
    return Row(children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 7),
        Expanded(
            child: SelectChip(label: items[i], selected: sel == i, onTap: () => onTap(i))),
      ]
    ]);
  }

  // ───────────── step 0: 기본 정보 ─────────────
  Widget _basic() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      children: [
        _card('1. 팀 이름',
            child: TextField(
              maxLength: 20,
              decoration: _deco('팀 이름을 입력하세요'),
            )),
        _card('2. 소개글',
            sub: '어떤 팀인지 짧게 소개해 주세요.',
            child: TextField(
              maxLines: 3,
              maxLength: 60,
              decoration: _deco('예) 매일 30분 운동 인증하는 팀이에요!'),
            )),
        _card('3. 팀 인원',
            sub: '양 팀 인원을 같게 맞춰 배틀해요.',
            child: _chipRow(_sizes, size, (i) => setState(() => size = i))),
        _card('4. 주 몇 회',
            sub: '일주일에 몇 번 인증할까요?',
            child: _chipRow(_freqs, freq, (i) => setState(() => freq = i))),
        _card('5. 인증 방법',
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: BC.oSoft, borderRadius: BorderRadius.circular(13)),
              child: Row(children: const [
                Icon(Icons.location_on_rounded, color: BC.oMain, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('GPS 위치 인증 · 팀 챌린지는 반경 제한 없이 등록 위치에서 인증해요.',
                      style: TextStyle(
                          fontSize: 13, color: BC.ink2, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ]),
            )),
        _card('6. 예치코인',
            sub: '참여 시 각자 거는 코인이에요. (코인)',
            child: _chipRow(_deposits, deposit, (i) => setState(() => deposit = i))),
      ],
    );
  }

  // ───────────── step 1: 공개 설정 ─────────────
  Widget _visibility() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      children: [
        _visCard(true, '공개', Icons.public_rounded, '탐색 목록에 노출되고, 누구나 바로 참여할 수 있어요.'),
        const SizedBox(height: 12),
        _visCard(false, '비공개', Icons.lock_rounded, '탐색에 노출되지 않아요. 방 코드를 아는 사람만 참여할 수 있어요.'),
        const SizedBox(height: 18),
        NoteBox(
          icon: Icons.verified_user_rounded,
          child: Text(
              isPublic
                  ? '공개 팀은 인원이 모이면 바로 배틀이 시작돼요.'
                  : '비공개 팀을 만들면 방 코드가 생성돼요. 친구에게 코드를 공유해 모아보세요.',
              style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
        ),
      ],
    );
  }

  Widget _visCard(bool value, String title, IconData icon, String desc) {
    final on = isPublic == value;
    return GestureDetector(
      onTap: () => setState(() => isPublic = value),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: on ? BC.oSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? BC.oMain : BC.line, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: on ? BC.oMain : BC.bg, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: on ? Colors.white : BC.ink3, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: on ? BC.oMain : BC.ink)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.4)),
                ],
              ),
            ),
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? BC.oMain : BC.ink3),
          ],
        ),
      ),
    );
  }

  void _onCreate() {
    if (isPublic) {
      Navigator.of(context).pop();
      showBoosterToast(context, '공개 팀을 만들었어요! 팀원을 모아보세요.');
    } else {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OwnerCodeScreen(code: '7K2Q')));
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BC.ink3),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.oMain, width: 1.5)),
      );
}

/// 방장 화면 — 방 코드 공유 + 모집 현황 + 챌린지 시작
class OwnerCodeScreen extends StatelessWidget {
  final String code;
  const OwnerCodeScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '방장 화면'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_rounded, color: BC.oMain, size: 30),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('비공개 팀이 만들어졌어요',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('아래 방 코드를 친구에게 공유해 팀원을 모아보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    decoration: BoxDecoration(
                      gradient: BC.grad,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: BC.ctaShadow,
                    ),
                    child: Column(
                      children: [
                        const Text('방 코드',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(code,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _ghostBtn(Icons.copy_rounded, '코드 복사', () {
                        Clipboard.setData(ClipboardData(text: code));
                        showBoosterToast(context, '방 코드를 복사했어요.');
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ghostBtn(Icons.ios_share_rounded, '공유하기',
                          () => showBoosterToast(context, '공유 시트를 여는 중…')),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  const Text('모집 현황',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Row(children: const [
                          Text('1 / 10명',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Spacer(),
                          Text('방장(나) 포함',
                              style: TextStyle(
                                  fontSize: 13, color: BC.ink2, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 7, runSpacing: 7, children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration:
                                const BoxDecoration(color: BC.oMain, shape: BoxShape.circle),
                            child: const Text('나',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                          for (int i = 0; i < 9; i++)
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: const Color(0xFFD6D4CF), width: 1.5)),
                              child: const Icon(Icons.add_rounded,
                                  size: 15, color: Color(0xFFC2C0BB)),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: PrimaryButton(
                label: '챌린지 시작하기',
                enabled: false,
                onTap: () {},
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text('인원이 모이면 시작할 수 있어요',
                  style: TextStyle(fontSize: 12, color: BC.ink3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BC.line, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: BC.oMain),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: BC.ink)),
          ],
        ),
      ),
    );
  }
}
