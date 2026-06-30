# 6차 — 시나리오 기반 코드리뷰 + 명세 대조 + 실패 테스트 고정(RED)

> 방식: B축 형의 워크플로우 모방 — 코드리뷰어 2개 레인(동시성/로직) 병렬 발견 → **A축 계획서·deep-interview 명세 대조** → 실패 테스트(RED)로 고정 → (수정은 다음 주 BS-25).
> 작성/개정: 2026-06-30 / 브랜치: `test/BS-30-backend-validation-a-axis` / **프로덕션 코드 미수정, 커밋 없음.**
> 명세 출처: A축 백엔드 구현 계획(RALPLAN-DR, Phase 1~4) + Booster 제품 기획서(deep-interview).
> ⚠️ BS-30(부하측정 1~5차)은 서로 다른 유저로 돌려 **단일 유저 동시요청 레이스 / 다일 상태머신**을 못 잡음. 이번 6차가 그 사각지대.

---

## 0. 핵심 결론 (명세 대조 후)

| 구분 | 건수 | 항목 |
|------|------|------|
| 🔴🟡 **확정 버그 (RED 테스트로 증명됨)** | **7건** | C1, C2, C4, C5, C6, C7(동시성 6) + B2(로직) + B3(로직) ※B1 일부 |
| 🟡 **결정 필요 (명세 공백)** | 3건 | B1(보상 타이밍), B2(가입일 정책), B3(차단 범위) — 일부는 버그이자 정책 |
| ❌ **오판 정정 (버그 아님)** | 1건 | B4 — Phase 3 명세상 의도된 동작. 테스트를 GREEN 특성화로 반전 |

**가장 강력한 발견:** C2·C4는 **명세가 해법을 직접 명시했는데 코드가 미구현**한 케이스 → 반박 불가 버그.
> 명세(공통 고려사항 > 스케줄러 > 멱등성): "RecoveryMission 상태 업데이트: **WHERE status='PENDING' 조건으로 중복 처리 방지**", "PersonalCheckIn: UNIQUE + **ON CONFLICT DO NOTHING**"
> 명세(Phase 2): "UNIQUE(userId, date) **위반 시 409 반환**"
> → 코드는 평범한 JPA `save()` + 더티체크라 셋 다 미적용.

---

## 1. 확정된 구조적 사실

- 프로덕션 PostgreSQL **READ_COMMITTED**, **`@Version` 전무**, **`@DynamicUpdate` 없음**(UPDATE가 전체 컬럼 덮어씀)
- 비관적 락 `findByIdForUpdate`는 **UserRepository에만**, `CoinService.lockUser` 단일 호출
- `Streak.lastSuccessDate`는 write만, read 0회 / `UserRepository.existsByIdAndActiveTrue`는 선언만, 호출 0회
- `DataIntegrityViolationException` 전용 핸들러 없음 → `handleGeneral` → HTTP 500
- 스케줄러가 명세의 `ON CONFLICT DO NOTHING` / `WHERE status='PENDING'`를 **미구현** (평범한 save/더티체크)

---

## 2. 최종 분류 표 (심각도 × 명세 대조 × RED 증거)

| # | 버그 | 심각도 | 명세 대조 | RED 테스트 & 증거 |
|---|------|--------|-----------|-------------------|
| **C2** | 동시 performRecovery 이중처리 (B축 버그 등가물) | 🔴 | **명세 위반** — "WHERE status='PENDING'" 미구현 | `C2ConcurrentRecoveryTest` → RECOVERY_SUCCESS 거래 **2행**(기대1), 잔액 400(기대450), 출석+2 |
| **C4** | 첫 인증 동시요청 UNIQUE 위반 누출 | 🔴 | **명세 위반** — "위반 시 409" 인데 500 | `C4DuplicateCheckInLeakTest` → 실패측 예외가 `DataIntegrityViolationException`(원시, →500), `BusinessException(DUPLICATE_CHECK_IN)` 아님 |
| **C1** | 코인 lost update | 🔴 | **불변식 위반** — Principle 2 "SUM(amount)=balance 항상 성립" | `C1CoinLostUpdateTest` → `coin_balance=958 ≠ SUM=920` (38코인 소실) |
| **C5** | Streak lost update | 🔴 | 상태머신 정합성 위반 | `C5StreakLostUpdateTest` → 30/30 라운드 `current_streak=5`(기대6), 체크인 +1 전부 소실 |
| **C6** | 스케줄러 만료(`<=`) vs 수행(`isAfter`) 경계 불일치 | 🟡 | **명세 위반** — 명세는 수행조건 "현재<deadlineAt"(strict), 코드는 `<=` | `C6BoundaryDoubleChargeTest` → deadline==now서 총 차감 **150**(=-50-100) |
| **C7** | 스케줄러 멱등성 단일인스턴스 의존 | 🟡 | **명세 위반** — "ON CONFLICT DO NOTHING" 미구현 (순차는 우연히 OK, 동시 실패) | (동시성 베이스로 재현 가능; 우선순위 낮음) |
| **B2** | 가입일 off-by-one | 🟡 | **명세 공백 + 코드 버그** — 명세는 "모든 활성 User"라 면제 언급 없음; 코드가 면제 추가하다 `isAfter`로 off-by-one | `RecoveryScenarioBugTest.joinedYesterday_shouldNotGetRecoveryPending` → 가입일==어제 유저에 RECOVERY_PENDING 생성됨 |
| **B3** | 탈퇴 후 토큰 가드 누락 | 🟡 | **명세 공백** — 명세는 "탈퇴 후 로그인 불가"만 요구, 타 API 침묵 | `WithdrawnUserGuardTest.withdrawnUser_cannotCheckIn / cannotPerformRecovery` → 탈퇴 유저가 인증·복귀 성공 |
| **B1** | 잠정 스트릭에 영구 마일스톤 보상 지급 | 🟡 | **명세 공백** — reward-repeat은 명세가 [미결] 명시; 잠정스트릭 상호작용 미고려. (연속성 자체는 명세대로 복귀흐름이 처리) | `StreakContinuityScenarioTest.gapBrokenStreak_doesNotGrantSevenDayMilestoneReward` → 끊긴 스트릭이 7일째 도달해 100코인 부당 지급 |
| ~~**B4**~~ | ~~복귀 당일 출석 미인정~~ | ❌ | **버그 아님** — Phase 3 "복귀는 오늘 레코드 생성 안 함, 오늘 일반인증 허용, 이중카운트 없음" 명시 | `RecoveryScenarioBugTest.recovery_doesNotCreateTodayRecord_butNormalCheckInStillAllowed` → **GREEN 특성화**로 반전 |

> 참고: `StreakContinuityScenarioTest.gapDay_breaksStreak…`(streak가 갭에도 +1)는 명세 모델상 "갭은 복귀흐름이 정리"이므로 **단독 버그는 아님**. 단 위 B1(보상 타이밍)의 전제를 재현하는 보조 테스트로 유지.

---

## 3. 명세가 직접 답을 준 항목 (정정 사항)

| 질문 | 명세 답 | 결과 |
|------|---------|------|
| 복귀 시 스트릭 +1? | "Streak 유지: currentStreak 변화 없음" | 코드(`keepAlive`) 정확 — **버그 아님** |
| 복귀 당일을 오늘 출석으로? | "복귀가 오늘 PersonalCheckIn 생성 안 함, 오늘 일반인증 허용" | **B4 오판 — 의도된 동작.** 테스트 GREEN 반전 |
| 스트릭 연속성 강제? | "미인증→복귀미션→실패 시 초기화" (복귀흐름이 책임) | B1 연속성 부분은 명세대로. 잔존 이슈는 보상 타이밍뿐 |
| 보상 반복 지급? | Phase 2 [미결] "단회/반복 미명시 → 제품 책임자 확인" | 이미 알려진 공백. 결정 필요 |

⚠️ **명세 자체 모순(팀에 문구 정리 요청):** Phase 3 제목 "복귀 성공 후 **당일 추가 인증 불가**" vs 본문 "오늘의 일반 인증은 **허용**".

---

## 4. 핵심 처방 (다음 주 BS-25에서 수정)

1. **coin/attendance/streak 트랜잭션은 진입 시 User를 `findByIdForUpdate`로 락 로드** → C1·C5 동시 해결
2. **미션/체크인 상태 전이를 조건부 원자 UPDATE(`WHERE status=...`) 또는 비관락**으로 보호 → C2·C6 (명세가 명시한 방식)
3. **`DataIntegrityViolationException` → 409(`DUPLICATE_CHECK_IN`) 핸들러 추가** → C4 (저비용 즉효)
4. **스케줄러 INSERT를 `ON CONFLICT DO NOTHING`(또는 건별 트랜잭션)** → C7 (명세대로)
5. **active 가드 연결**(필터 또는 쓰기서비스 진입부, `existsByIdAndActiveTrue` 활용) → B3
6. **가입일 경계 `!isBefore(yesterday)`로 수정** → B2 (+ 명세에 면제 정책 명문화)
7. **마일스톤 보상을 "확정 스트릭"에만** 지급(또는 복귀 PENDING 동안 보류) → B1

## 5. 팀/제품 결정 필요 (공백)
- **B1**: 보상 반복 지급 여부(명세 [미결]) + 잠정 스트릭 보상 보류 여부
- **B2**: 가입 당일 미인증 면제 정책 (명세 명문화)
- **B3**: 탈퇴(비활성) 후 차단 범위 — 로그인만? 전 API? 토큰 무효화?
- **B4**: Phase 3 명세 문구 모순 정리

---

## 6. 산출물
- **로직 RED 테스트**: `personalcheckin/StreakContinuityScenarioTest.java`, `recovery/RecoveryScenarioBugTest.java`(B2 RED + B4 GREEN), `user/WithdrawnUserGuardTest.java`
- **동시성 RED 테스트**: `concurrency/ConcurrencyTestBase.java`, `FixedClockConfig.java`, `C1CoinLostUpdateTest`, `C2ConcurrentRecoveryTest`, `C4DuplicateCheckInLeakTest`, `C5StreakLostUpdateTest`, `C6BoundaryDoubleChargeTest`
- **테스트 인프라**: `build.gradle`(Testcontainers 의존성 + `systemProperty 'api.version','1.44'` — 이 머신 Docker API 1.54 협상 이슈 우회), `src/test/resources/application-ct.yml`(동시성 전용 PG 프로파일, H2 `test`와 분리)
- 동시성은 **Testcontainers PostgreSQL(postgres:16-alpine)** + Flyway V6~V8 적용 확인. 5건 모두 안정 재현.

> ⚠️ 로직 RED 테스트(B1·B2·B3)는 **의도적으로 실패**(버그 증명). 기본 `./gradlew test`가 빨갛게 나오는 게 정상. 수정(BS-25) 시 GREEN 전환. 빌드를 초록으로 유지하려면 `@Tag`/`@Disabled("BS-30 버그핀")` 부여 가능(현재는 RED 유지).
