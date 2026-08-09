import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart';
import '../main_scaffold.dart';
import 'coin_history_screen.dart';

/// 마이페이지 — `GET /api/users/me`, `GET /api/users/me/coins`,
/// `DELETE /api/users/me`.
///
/// 알림 설정 화면은 뺐다. 백엔드에 설정 API도 알림 API도 없어서
/// (`integration/a-b-axis`), 토글을 둬 봐야 아무 데도 저장되지 않는다.
/// 프로필 수정(닉네임/이미지)도 같은 이유로 없다.
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});
  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  String _nickname = '사용자';
  String _email = '';
  AppUser? _user;
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    _nickname = Session.nickname ?? '사용자';
    _email = Session.email ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await UserService.fetchMe();
      if (!mounted) return;
      setState(() {
        _user = user;
        _nickname = user.nickname;
        if (user.email.isNotEmpty) _email = user.email;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    _toLogin();
  }

  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text('탈퇴하면 코인과 인증 기록이 모두 사라져요. 정말 탈퇴할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소', style: TextStyle(color: BC.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('탈퇴하기', style: TextStyle(color: Color(0xFFE5484D))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _withdrawing = true);
    try {
      await UserService.withdraw();
      if (!mounted) return;
      _toLogin();
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _withdrawing = false);
    }
  }

  void _toLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

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
              child: const Row(
                children: [
                  Text('마이페이지',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Spacer(),
                  NotificationBell(),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: BC.oMain,
                child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _profileCard(),
                  const SizedBox(height: 22),
                  _section('내 활동', [
                    _row(Icons.receipt_long_rounded, BC.oMain, BC.oSoft, '코인 내역',
                        sub: '적립·차감 내역 보기',
                        value: _user == null ? null : CoinPill.format(_user!.coinBalance),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const CoinHistoryScreen()))),
                    _row(Icons.verified_rounded, BC.green, BC.greenSoft, '누적 출석',
                        value: _user == null ? null : '${_user!.totalAttendance}일'),
                  ]),
                  const SizedBox(height: 18),
                  _section('계정', [
                    _row(Icons.logout_rounded, BC.ink3, const Color(0xFFF1F2F5), '로그아웃',
                        onTap: _logout),
                    _row(Icons.person_off_rounded, const Color(0xFFE5484D),
                        const Color(0xFFFDEAEA), '회원 탈퇴',
                        danger: true, onTap: _withdrawing ? null : _withdraw),
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
              // 프로필 수정 API가 없어서(백엔드 UserController는 조회·코인·탈퇴만
              // 제공) 편집 배지는 두지 않는다.
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, size: 32, color: BC.oMain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nickname,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis),
                    if (_email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(_email,
                          style: const TextStyle(fontSize: 13, color: BC.ink3),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
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
                Text(CoinPill.format(_user?.coinBalance ?? Session.coinBalance),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: BC.oMain)),
                const SizedBox(width: 3),
                const Text('코인',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: BC.ink2)),
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
      {String? sub, String? value, String? badge, bool danger = false, VoidCallback? onTap}) {
    final content = Padding(
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
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
