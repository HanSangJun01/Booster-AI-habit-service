import 'package:flutter/material.dart';
import '../core/session.dart';
import '../theme/booster_theme.dart';

/// 금화 점 (S/$ 표시)
class CoinDot extends StatelessWidget {
  final double size;
  final String symbol;
  const CoinDot({super.key, this.size = 18, this.symbol = 'S'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [BC.gold1, BC.gold2],
        ),
      ),
      child: Text(
        symbol,
        style: TextStyle(
          color: const Color(0xFF9A5800),
          fontWeight: FontWeight.w900,
          fontSize: size * 0.6,
        ),
      ),
    );
  }
}

/// 코인 잔액 알약.
///
/// [amount]를 주지 않으면 Session에 마지막으로 반영된 잔액을 보여준다.
/// 체크인·복귀 미션 응답이 갱신된 잔액을 함께 주기 때문에(`coinBalance`),
/// 별도 조회 없이도 최신 값이 유지된다.
class CoinPill extends StatelessWidget {
  final String? amount;
  const CoinPill({super.key, this.amount});

  /// 1234 → "1,234"
  static String format(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final fixed = amount;
    if (fixed != null) return _pill(fixed);
    // 잔액을 구독한다. 부모가 const라 다시 빌드되지 않아도 값이 바뀌면 여기만
    // 갱신된다.
    return ValueListenableBuilder<int>(
      valueListenable: Session.coinBalanceListenable,
      builder: (_, value, __) => _pill(format(value)),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 13, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BC.oSoft2, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinDot(size: 18),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: BC.oMain, fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }
}

/// 알림 벨 + 빨간 배지.
///
/// 백엔드에 알림 API가 없어서(`integration/a-b-axis`에 Notification 컨트롤러
/// 자체가 없다) 안 읽은 개수를 조회할 방법이 없다. [count]를 명시적으로 넘긴
/// 경우에만 배지를 띄우고, 기본값은 배지 없음이다.
class NotificationBell extends StatelessWidget {
  final int count;
  final Color color;
  const NotificationBell({super.key, this.count = 0, this.color = const Color(0xFF3A3A3E)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 25, color: color),
          if (count > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BC.oMain,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BC.bg, width: 2),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 로고(엠블럼 + 이탤릭 Booster) + 코인 + 벨 헤더
class BoosterHeader extends StatelessWidget {
  final bool showBell;
  const BoosterHeader({super.key, this.showBell = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(
        children: [
          Image.asset('assets/booster_emblem.png', width: 34, height: 34),
          const SizedBox(width: 7),
          const Text('Booster',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  color: BC.oMain,
                  letterSpacing: -0.3)),
          const Spacer(),
          const CoinPill(),
          if (showBell) ...[
            const SizedBox(width: 10),
            const NotificationBell(),
          ],
        ],
      ),
    );
  }
}

/// 뒤로가기 + 가운데 제목 + (옵션) 우측 위젯 앱바
class BackAppBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const BackAppBar({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 10),
      child: Row(
        children: [
          InkResponse(
            onTap: () => Navigator.of(context).maybePop(),
            radius: 24,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.chevron_left_rounded, size: 28, color: BC.ink),
            ),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                // 챌린지 제목을 그대로 넘기는 화면이 있다(team_waiting 등).
                // 제한이 없으면 긴 제목이 앱바를 두세 줄로 늘린다.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          // 폭을 40으로 고정하면 trailing이 그보다 넓을 때 잘린다 — CoinPill을
          // 넘기는 화면들이 실제로 오버플로였다. 40은 trailing이 없을 때 뒤로가기
          // 버튼과 균형을 맞추기 위한 '최소'값이지 상한이 아니다.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    );
  }
}

/// 둥근 카드
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final BorderRadius? radius;
  final Border? border;
  final List<BoxShadow>? shadow;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = BC.card,
    this.radius,
    this.border,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius ?? BorderRadius.circular(20),
        border: border,
        boxShadow: shadow ?? BC.cardShadow,
      ),
      child: child,
    );
  }
}

/// 선택형 칩
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dashed;
  const SelectChip(
      {super.key, required this.label, this.selected = false, this.onTap, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 가로 패딩이 없으면 폭을 스스로 정하는 자리(가로 ListView 등)에서 글자에
        // 딱 붙어 잘린 것처럼 보인다. Expanded로 감싼 쪽은 폭을 부모가 정하므로
        // 이 값의 영향을 받지 않는다.
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? BC.oSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? BC.oMain : BC.line,
            width: 1.5,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? BC.oMain : BC.ink2)),
      ),
    );
  }
}

/// 안내 노트(아이콘 + 텍스트, 연주황 배경)
class NoteBox extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final Color bg;
  final Color iconColor;
  const NoteBox(
      {super.key,
      required this.icon,
      required this.child,
      this.bg = BC.oSoft,
      this.iconColor = BC.oMain});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 큰 그라데이션 CTA 버튼
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final bool enabled;
  const PrimaryButton({
    super.key,
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? BC.grad : null,
          color: enabled ? null : const Color(0xFFD4D2CD),
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? BC.ctaShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// 작은 태그
class MiniTag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const MiniTag(this.text, {super.key, this.bg = BC.tagBg, this.fg = const Color(0xFF86868B)});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );
}

/// 로그인/회원가입 등에서 쓰는 라벨 + 입력 필드
class BoosterTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  const BoosterTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: BC.line, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: BC.ink2)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
              fontSize: 15, color: BC.ink, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: BC.ink3, fontWeight: FontWeight.w500),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: BC.oMain, width: 1.8)),
            errorBorder: border.copyWith(
                borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1.5)),
            focusedErrorBorder: border.copyWith(
                borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1.8)),
            errorStyle: const TextStyle(
                fontSize: 11.5, color: Color(0xFFE5484D), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// 가벼운 토스트
void showBoosterToast(BuildContext context, String msg) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: Text(msg, textAlign: TextAlign.center),
    behavior: SnackBarBehavior.floating,
    backgroundColor: BC.ink.withValues(alpha: .9),
    duration: const Duration(milliseconds: 1600),
    margin: const EdgeInsets.fromLTRB(40, 0, 40, 110),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}
