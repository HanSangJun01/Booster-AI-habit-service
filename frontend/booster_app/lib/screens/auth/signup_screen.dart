import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await _signup(_nicknameCtrl.text.trim(), _emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
        (route) => false,
      );
    } catch (_) {
      setState(() => _errorText = '회원가입 중 문제가 발생했어요. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 백엔드 회원가입 API 연동 지점 (POST /api/auth/signup).
  /// 현재는 목업으로 항상 성공 처리하며, 응답의 userId 자리에 임시값(1)을 채운다.
  /// 실제 연동 시 ApiClient.post('/auth/signup', body: {...})의 data.userId로 교체한다.
  Future<void> _signup(String nickname, String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 600));
    Session.set(userId: 1, nickname: nickname);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '회원가입'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      BoosterTextField(
                        controller: _nicknameCtrl,
                        label: '닉네임',
                        hint: '닉네임을 입력하세요',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '닉네임을 입력하세요' : null,
                      ),
                      const SizedBox(height: 16),
                      BoosterTextField(
                        controller: _emailCtrl,
                        label: '이메일',
                        hint: '이메일을 입력하세요',
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      BoosterTextField(
                        controller: _passwordCtrl,
                        label: '비밀번호',
                        hint: '6자 이상 입력하세요',
                        obscureText: _obscure1,
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure1
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20,
                              color: BC.ink3),
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                        ),
                        validator: (v) =>
                            (v == null || v.length < 6) ? '비밀번호는 6자 이상이어야 해요' : null,
                      ),
                      const SizedBox(height: 16),
                      BoosterTextField(
                        controller: _confirmCtrl,
                        label: '비밀번호 확인',
                        hint: '비밀번호를 다시 입력하세요',
                        obscureText: _obscure2,
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure2
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20,
                              color: BC.ink3),
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                        ),
                        validator: (v) =>
                            (v != _passwordCtrl.text) ? '비밀번호가 일치하지 않아요' : null,
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(_errorText!,
                            style: const TextStyle(
                                color: Color(0xFFE5484D),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: _loading ? '가입 중...' : '회원가입',
                        onTap: _submit,
                        enabled: !_loading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return '이메일을 입력하세요';
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
  return ok ? null : '올바른 이메일 형식이 아니에요';
}
