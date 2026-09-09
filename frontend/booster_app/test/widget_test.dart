// Booster 앱 기본 스모크 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:booster_app/main.dart';

void main() {
  testWidgets('앱이 로그인 화면으로 시작한다', (WidgetTester tester) async {
    await tester.pumpWidget(const BoosterApp());

    // 로그인 화면의 핵심 요소가 보이는지 확인한다.
    expect(find.text('Booster'), findsWidgets);
    expect(find.text('로그인'), findsWidgets);
  });
}
