import 'package:flutter/material.dart';
import '../theme/booster_theme.dart';
import 'home/home_screen.dart';
import 'team/team_home_screen.dart';
import 'verify/verify_screen.dart';
import 'shop/shop_screen.dart';
import 'mypage/mypage_screen.dart';

/// 탭 전환을 어디서든 호출할 수 있게 해주는 스코프
class MainNavScope extends InheritedWidget {
  final int current;
  final void Function(int index) select;
  const MainNavScope({
    super.key,
    required this.current,
    required this.select,
    required super.child,
  });

  static MainNavScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MainNavScope>();
    assert(scope != null, 'MainNavScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(MainNavScope oldWidget) => current != oldWidget.current;
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;

  final _navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  final _roots = const [
    HomeScreen(),
    TeamHomeScreen(),
    VerifyScreen(),
    ShopScreen(),
    MyPageScreen(),
  ];

  void _select(int i) {
    if (i == _index) {
      // 같은 탭 재탭 → 해당 탭 루트로 pop
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainNavScope(
      current: _index,
      select: _select,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          final nav = _navKeys[_index].currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          } else if (_index != 0) {
            setState(() => _index = 0);
          }
        },
        child: Scaffold(
          backgroundColor: BC.bg,
          body: IndexedStack(
            index: _index,
            children: List.generate(5, (i) {
              return Navigator(
                key: _navKeys[i],
                onGenerateRoute: (settings) =>
                    MaterialPageRoute(builder: (_) => _roots[i], settings: settings),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 루트 화면 하단에 깔리는 내비게이션 바 (가운데 인증 FAB 강조)
class BoosterBottomNav extends StatelessWidget {
  const BoosterBottomNav({super.key});

  static const _items = [
    (Icons.home_rounded, '홈'),
    (Icons.groups_rounded, '팀'),
    (Icons.verified_rounded, '인증'),
    (Icons.storefront_rounded, '상점'),
    (Icons.person_rounded, '마이페이지'),
  ];

  @override
  Widget build(BuildContext context) {
    final scope = MainNavScope.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BC.line)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + (bottomInset > 0 ? bottomInset : 14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(5, (i) {
          final active = scope.current == i;
          final (icon, label) = _items[i];
          if (i == 2) return _CenterTab(active: active, onTap: () => scope.select(2));
          return Expanded(
            child: _Tab(
              icon: icon,
              label: label,
              active: active,
              onTap: () => scope.select(i),
            ),
          );
        }),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? BC.oMain : BC.ink3;
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CenterTab extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _CenterTab({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -26),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: BC.grad,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                        color: BC.o2.withOpacity(.45),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -22),
              child: const Text('인증',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: BC.oMain)),
            ),
          ],
        ),
      ),
    );
  }
}
