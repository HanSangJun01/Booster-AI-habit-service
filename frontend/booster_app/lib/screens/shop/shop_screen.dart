import 'package:flutter/material.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoosterHeader(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.storefront_rounded, size: 40, color: BC.oMain),
                    ),
                    const SizedBox(height: 18),
                    const Text('상점 준비 중',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('모은 코인으로 아이템을 교환할 수 있는\n상점을 준비하고 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5)),
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
}
