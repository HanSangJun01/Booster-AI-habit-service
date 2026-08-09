import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/auth_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'signup_screen.dart';


class LoginScreen extends StatefulWidget {
  /// 토큰 만료로 되돌아온 경우 true. 사용자는 자기가 왜 로그인 화면에 와 있는지
  /// 모르기 때문에, 그냥 빈 화면을 보여주면 앱이 튕긴 것처럼 느낀다.
  final bool sessionExpired;

  const LoginScreen({super.key, this.sessionExpired = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (widget.sessionExpired) {
      _errorText = '로그인이 만료됐어요. 다시 로그인해주세요';
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await AuthService.login(_emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
        (route) => false,
      );
    } on ApiException catch (e) {
      // 서버에 닿지 못한 경우(statusCode == null)와 자격증명 오류를 구분해서
      // 보여준다 — 서버가 안 떠 있는데 "비밀번호가 틀렸다"고 하면 헤맨다.
      setState(() => _errorText =
          e.statusCode == null ? e.message : '이메일 또는 비밀번호가 올바르지 않습니다');
    } catch (_) {
      setState(() => _errorText = '로그인 중 문제가 발생했어요. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 56),
                Center(
                  child: Column(
                    children: [
                      Image.asset('assets/booster_emblem.png', width: 72, height: 72),
                      const SizedBox(height: 12),
                      const Text('Booster',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              color: BC.oMain,
                              letterSpacing: -0.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text('오늘도 한 걸음, 검증으로 완성하는 습관',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                const SizedBox(height: 40),
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
                  hint: '비밀번호를 입력하세요',
                  obscureText: _obscure,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 20,
                        color: BC.ink3),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? '비밀번호는 6자 이상이어야 해요' : null,
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
                  label: _loading ? '로그인 중...' : '로그인',
                  onTap: _submit,
                  enabled: !_loading,
                ),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: _loading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SignupScreen())),
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(fontSize: 13.5, color: BC.ink2),
                        children: [
                          TextSpan(text: '아직 계정이 없으신가요? '),
                          TextSpan(
                              text: '회원가입',
                              style:
                                  TextStyle(color: BC.oMain, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
