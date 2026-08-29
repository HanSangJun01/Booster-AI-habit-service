import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/auth_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';
import 'login_screen.dart';

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
      // 가입 응답에는 토큰이 없어서 AuthService가 곧바로 로그인까지 이어서
      // 수행한다 — 여기서 별도로 로그인할 필요는 없다.
      await AuthService.signup(
          _nicknameCtrl.text.trim(), _emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
        (route) => false,
      );
    } on SignupAutoLoginException catch (e) {
      // 계정은 이미 만들어졌다. 이 화면에 남겨두면 사용자는 다시 가입을
      // 시도하고 이메일 중복만 보게 된다. 로그인 화면으로 돌려보내면서
      // 가입한 이메일을 넘겨 채워준다.
      if (!mounted) return;
      final nav = Navigator.of(context);
      // 보통은 로그인 화면 위에 올라와 있어서 pop이면 충분하다. 아닌 경로로
      // 열렸더라도 사용자가 빈 화면에 갇히지 않게 로그인 화면을 세운다.
      if (nav.canPop()) {
        nav.pop(e.email);
      } else {
        nav.pushReplacement(MaterialPageRoute(
            builder: (_) => LoginScreen(signedUpEmail: e.email)));
      }
    } on ApiException catch (e) {
      // 서버 검증 메시지(비밀번호 길이, 이메일 형식, 중복 등)를 그대로 보여준다.
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = '회원가입 중 문제가 발생했어요. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                        hint: '30자 이내로 입력하세요',
                        // 비밀번호와 마찬가지로 서버 제약(1~30자)을 미리 맞춘다.
                        // 여기서 안 막으면 31자가 그대로 나가서 400으로 튕기고,
                        // 어느 칸이 문제인지 알려주지 못한다.
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return '닉네임을 입력하세요';
                          if (value.length > 30) return '닉네임은 30자를 넘을 수 없어요';
                          return null;
                        },
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
                        // 서버 제약(`SignupRequest`)이 8~64자다. 여기서 미리
                        // 맞춰야 가입 요청이 검증 오류로 튕기지 않는다.
                        hint: '8자 이상 입력하세요',
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
                        validator: (v) {
                          if (v == null || v.length < 8) return '비밀번호는 8자 이상이어야 해요';
                          if (v.length > 64) return '비밀번호는 64자를 넘을 수 없어요';
                          return null;
                        },
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
