import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

class PersonalCreateScreen extends StatefulWidget {
  const PersonalCreateScreen({super.key});
  @override
  State<PersonalCreateScreen> createState() => _PersonalCreateScreenState();
}

class _PersonalCreateScreenState extends State<PersonalCreateScreen> {
  int title = 0;
  int period = 1; // 14일
  int freq = 2; // 3회
  int radius = 1; // 100m

  final _periods = ['7일', '14일', '21일', '30일'];
  final _freqs = ['1회', '2회', '3회', '4회', '5회', '6회', '7회'];
  final _radii = ['50m', '100m', '200m'];

  String get _exemptText {
    final n = freq + 1;
    final e = 7 - n;
    return e > 0
        ? '주 $n회 선택 시, 면제일 $e일이 제공돼요.'
        : '주 $n회는 매일 인증이라 면제일이 없어요.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(title: '챌린지 생성', trailing: const CoinPill()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                children: [
                  // 1. 제목
                  _card(
                    '1. 챌린지 제목',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          maxLength: 30,
                          onChanged: (v) => setState(() => title = v.length),
                          decoration: _inputDeco('챌린지 제목을 입력하세요'),
                        ),
                      ],
                    ),
                  ),
                  // 2. 최소 기간
                  _card(
                    '2. 최소 기간',
                    sub: '이 기간 동안은 챌린지를 종료할 수 없어요.',
                    child: Column(
                      children: [
                        _chipRow(_periods, period, (i) => setState(() => period = i)),
                        const SizedBox(height: 14),
                        NoteBox(
                          icon: Icons.verified_user_rounded,
                          child: const Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '최소 기간이 지나면 ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, color: BC.oMain, fontSize: 13)),
                            TextSpan(
                                text: '언제든 챌린지를 종료하고 코인을 정산할 수 있어요.',
                                style: TextStyle(fontSize: 13, color: BC.ink2, height: 1.4)),
                          ])),
                        ),
                      ],
                    ),
                  ),
                  // 3. 주 몇 회
                  _card(
                    '3. 주 몇 회',
                    sub: '일주일에 몇 번 진행할 건가요?',
                    child: Column(
                      children: [
                        _chipRow(_freqs, freq, (i) => setState(() => freq = i)),
                        const SizedBox(height: 14),
                        NoteBox(
                          icon: Icons.verified_user_rounded,
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: _exemptText,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, color: BC.oMain, fontSize: 13)),
                            const TextSpan(
                                text: '\n인증을 놓쳐도 면제일만큼은 패널티가 부과되지 않아요!',
                                style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5)),
                          ])),
                        ),
                      ],
                    ),
                  ),
                  // 4. 인증 위치
                  _card(
                    '4. 인증 위치',
                    sub: '등록한 위치 반경 안에서만 인증할 수 있어요.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 150,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFFEEF1F5), Color(0xFFE4E8EE)]),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD3D7DE)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.location_on_rounded, color: BC.oMain, size: 28),
                              SizedBox(height: 6),
                              Text('지도에서 위치 선택',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF8A8A92))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: const [
                            Icon(Icons.location_on_rounded, size: 17, color: BC.oMain),
                            SizedBox(width: 8),
                            Text('서울 서초구 반포한강공원',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text('인증 반경',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700, color: BC.ink2)),
                        const SizedBox(height: 9),
                        _chipRow(_radii, radius, (i) => setState(() => radius = i)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: PrimaryButton(
                label: '챌린지 만들기',
                trailingIcon: Icons.chevron_right_rounded,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BC.ink3),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: BC.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: BC.oMain, width: 1.5),
        ),
      );

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
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: SelectChip(
              label: items[i],
              selected: sel == i,
              onTap: () => onTap(i),
            ),
          ),
        ],
      ],
    );
  }
}
