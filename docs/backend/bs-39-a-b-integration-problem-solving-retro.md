# A/B축 통합 문제 해결 회고 — 신원 · 정합성 · 계약 정리

> 브랜치: `integration/a-b-axis` · 정리일: 2026-07-15
> 형식: 문제 → 적용한 해결 방식 → 해결 후보군 → 선정 이유(장점)
> 맥락: A축(개인 습관)과 B축(챌린지)을 통합하면서 B축의 X-User-Id 헤더 인증을 JWT로,
> 자체 stub(Coin/User/CheckIn)을 A축 실구현으로 이관했다. 통합 브랜치를 main에 PR하기 전
> 코드 리뷰에서 발견한 위험 요소를 문제-해결 관점으로 정리한다.

각 문제의 실제 구현 위치(`파일:라인`)를 근거로 정리한다.

---

## A. 신원(Identity) 정합성

### A-1. cheer의 userId/participantId 공간 혼용 — JWT principal 오전달
**위치**: `SocialController.sendCheer()`, `CheerService.sendCheer()`

- **문제**: JWT 통합 후 principal은 **userId**인데, 컨트롤러가 이를 `fromParticipantId`로 그대로 서비스에 넘겼다. 결과로 `cheer_emojis.from_participant_id`엔 userId가, `to_participant_id`엔 클라이언트가 준 participantId가 저장되어 **한 테이블에 두 ID 공간이 혼재**했다. 파급:
  - self-cheer 검증(`from.equals(to)`)이 서로 다른 공간을 비교 → **무력화**
  - 멤버십 검증이 **아예 없음** → 미참여자도 임의 챌린지에 응원 삽입 가능
  - DB `cheer_not_self` CHECK(`V5`)도 우연히 값이 겹치지 않는 한 방어 못 함
- **적용 방식**: 컨트롤러는 `@AuthenticationPrincipal Long userId`로 받아 서비스에 userId 전달. 서비스에서 `findConfirmedByUserAndChallenge`로 **from을 CONFIRMED 참여자로 해석**(미참여 시 403 `NOT_A_PARTICIPANT`), `to`도 **같은 챌린지 참여자인지 검증**(아니면 400 `INVALID_CHEER_TARGET`), 그다음 **participantId 공간에서** self-cheer 차단(400 `SELF_CHEER`). DB엔 진짜 participantId 저장.
- **후보군**
  - 컨트롤러에서 userId→participantId 변환 후 서비스 시그니처 유지 — 변환 책임이 컨트롤러에 새고, to 검증 위치 애매
  - **서비스가 fromUserId를 받아 참여자 해석+양측 멤버십 검증** ✅
  - DTO에 fromParticipantId를 클라이언트가 직접 보내게 — 위조 가능(다른 참여자 사칭)
- **선정 이유(장점)**
  - **신원 위조 차단**: from을 서버가 JWT userId로부터 도출 → 클라이언트가 타인 사칭 불가
  - **chat 경로와 정책 통일**: `TeamChatService`가 `p.getUserId().equals(senderId)`로 멤버십을 검증하는 것과 동일한 모델 → 소셜 기능 일관
  - **DB 제약 유효화**: from/to 모두 participantId라 `cheer_not_self` CHECK가 실제 방어선이 됨
  - **단일 지점 검증**: 컨트롤러가 아닌 서비스에서 해석 → 우회 경로 없음

---

## B. 회계 정합성 (코인 총량 보존)

### B-1. 예치금 차감 TOCTOU — 비관적 락은 있었으나 임계영역이 좁았다
**위치**: `CoinServiceAdapter.deduct()` → `CoinService.chargeStrict()`

- **문제**: 핵심은 "락이 없었다"가 아니라 **"락이 보호하는 구간(임계영역)이 차감에만 걸려 있었다"** 이다. B축 `deduct`가 A축 실구현에 연결되며 아래 2단계로 나뉘었다.
  1. `getBalance` **무락 사전검사**(readOnly 트랜잭션, `findById`) — 여기서 "부족하면 거절" 판단(**Time Of Check**)
  2. `charge` **비관적 락 차감**(별도 트랜잭션, 부족 시 예외 없이 **잔액까지만 클램핑**, **Time Of Use**)

  `charge`는 이미 `findByIdForUpdate`(PESSIMISTIC_WRITE)로 유저 행을 잠갔지만, **판단(①)이 그 락 밖의 별도 트랜잭션**에서 일어났다. ①의 스냅샷과 ②의 실행 사이에 **락이 풀려 있어** 전형적 **TOCTOU**가 성립한다. 게다가 `charge`가 클램핑(거절이 아니라 조용히 부분 차감)이라 두 번째 요청이 **실패하지 않고 통과**한다.

  ```text
  잔액 100, 같은 유저가 챌린지 A·B에 동시 참여
    스레드1(A)                    스레드2(B)
    getBalance=100 (무락)         getBalance=100 (무락)     ← 둘 다 옛 값으로 "충분" 판단
    charge: 🔒 100 차감 → 0       charge: 🔒 min(100,0)=0 차감  ← 클램핑, 예외 없음
    CONFIRMED                     CONFIRMED                 ← 실제 100만 냈는데 둘 다 확정
  ```
  정산은 `totalPool = 예치금 × 참여자수`로 계산하므로 **장부상 풀 > 실제 징수** → 코인이 무에서 발행된다.
- **적용 방식**: 락의 **대상**(유저 행 1개)은 그대로 두고, 락이 보호하는 **임계영역을 `{차감}`에서 `{검사 + 차감}`으로 확장**한다. `CoinService.chargeStrict()` 신설 — `lockUser`(PESSIMISTIC_WRITE)로 **먼저 락을 잡은 뒤 그 안에서** 잔액검사 → (부족 시 `InsufficientCoinException`, 클램핑 안 함) → 차감을 **단일 트랜잭션**으로 수행. 어댑터 `deduct`는 무락 사전검사를 버리고 `chargeStrict`에 위임.
  - **왜 어댑터에 검사를 두면 안 되나**: DB 행 락은 `@Transactional` 메서드 경계에서 풀린다. 어댑터가 `getBalance`→`charge` 두 번 호출하면 **하나의 락 홀드로 두 호출을 묶을 수 없다.** 검사와 차감을 원자화하려면 검사가 **락이 살아있는 곳(charge 트랜잭션 내부)** 으로 들어가야 한다.
- **후보군**
  - 어댑터에 무락 사전검사 유지(기존) — 검사·차감이 다른 트랜잭션이라 락이 풀려 TOCTOU
  - **락 임계영역을 검사까지 확장(차감측 `chargeStrict`, 한 락·한 트랜잭션)** ✅
  - 참여 서비스에서 유저 행까지 추가 락 — 락 **대상**을 늘리는 접근. 임계영역만 넓히면 되는데 락 지점이 이원화되어 교착면·복잡도 증가
  - 낙관적 버전(`@Version`) — 참가 신청은 경합이 실재해 충돌 재시도가 잦음 + `users` 스키마 변경
  - DB `CHECK(balance >= 0)` — 위반이 트랜잭션을 rollback-only로 오염, "부족" 구분 어려움
- **선정 이유(장점)**
  - **TOCTOU 원천 차단**: 검사와 차감이 같은 행 락 안에서 원자적 → 동시 두 요청이 직렬화되어 두 번째는 잔액 0을 보고 예외로 거절
  - **최소 확장**: 락 대상을 늘리지 않고 **임계영역만** 넓혀 해결 → 병목·교착 위험 최소(코인은 짧은 트랜잭션)
  - **락 소유자 일원화**: 코인 락은 코인 서비스가 소유(단일 진실 원천 유지) → 호출부는 정책만 선택
  - **기존 charge 보존**: 클램핑이 필요한 경로(정산 환불 등)는 `charge` 그대로, 거절이 필요한 참가만 `chargeStrict` → 시맨틱 분리
  - **스키마 무변경**: 기존 `findByIdForUpdate` 락 재사용

---

## C. 오류 응답 정합성

### C-1. IllegalArgumentException → 500 을 400 으로 매핑
**위치**: `GlobalExceptionHandler` (`@ExceptionHandler(IllegalArgumentException)`)

- **문제**: 도메인 검증 실패로 던지는 `IllegalArgumentException`(예: cheer self-check 이전 버전, `charge amount must be >= 0`)이 전역 핸들러에 매핑이 없어 catch-all(`Exception`)로 떨어져 **500**을 반환했다. 클라이언트엔 "잘못된 요청"이 "서버 오류"로 표기.
- **적용 방식**: `@ExceptionHandler(IllegalArgumentException) → 400 ILLEGAL_ARGUMENT` 추가.
- **후보군**
  - 각 서비스에서 BusinessException.badRequest로 바꿔 던지기 — 호출부 전부 수정, 누락 위험
  - **전역 핸들러에 IAE→400 안전망 추가** ✅
  - 그대로 500 방치 — 클라이언트 오해·모니터링 오탐
- **선정 이유(장점)**
  - **일관성**: 기존 `IllegalStateException→409` 매핑과 같은 결(잘못된 인자=400)
  - **안전망**: 서비스가 미처 감싸지 못한 IAE도 4xx로 표준화 → 500 오탐 감소
  - **최소 변경**: 핸들러 1개 추가로 전역 적용

---

## D. 계약(Contract) 정리

### D-1. 데드 포트 UserService 제거
**위치**: `shared/contract/UserService.java`, `UserServiceAdapter.java` (삭제)

- **문제**: B축 개발 중 참여 검증용으로 만든 `UserService` 포트+어댑터가, 실제 참여 검증이 `findConfirmedByUserAndChallenge`로 대체되며 **소비처 0**(자기 자신 implements 외 참조 없음)인 잔재로 남았다.
- **적용 방식**: 프로덕션·테스트 참조가 0임을 확인한 뒤 두 파일 삭제.
- **후보군**
  - 방치 — 죽은 코드가 "축 간 계약"으로 오인될 소지
  - `@Deprecated` 표시만 — 여전히 로딩·혼동
  - **삭제** ✅
- **선정 이유(장점)**
  - **계약 표면 축소**: 실제 사용되는 포트(Coin/PersonalCheckIn)만 남아 통합 지점이 명확
  - **오해 제거**: 살아있는 어댑터로 오인해 유지보수하는 비용 차단
  - **안전**: 참조 0 확인 후 삭제라 회귀 없음

---

## E. 회귀 방어 (테스트)

### E-1. cheer 신원/멤버십 · chargeStrict 단위 테스트 추가
**위치**: `CheerServiceTest`, `CoinServiceStrictChargeTest`

- **문제**: 위 A-1(cheer)이 단위 테스트로 안 걸렸다. 원인 — cheer 서비스 테스트 부재 + test 프로파일(H2 `create-drop`)이 Flyway-only CHECK(`cheer_not_self`)를 적용하지 않음. B-1(TOCTOU)도 검증 부재.
- **적용 방식**:
  - `CheerServiceTest`(Mockito) 4케이스: happy(from을 userId가 아닌 participantId로 저장 검증)·미참여자 403·타챌린지 대상 400·self-cheer 400
  - `CoinServiceStrictChargeTest` 3케이스: 충분 시 정확히 차감(클램핑 아님)·부족 시 예외+잔액 불변·음수 거절
- **후보군**
  - 통합 테스트(@SpringBootTest)만 — 느리고, H2 CHECK 미적용 문제 그대로
  - **서비스 단위 테스트(Mockito)로 로직 직접 검증** ✅
  - 수동 검증만 — 회귀 방어 안 됨
- **선정 이유(장점)**
  - **핵심 로직 직접 검증**: DB 제약에 의존하지 않고 서비스의 신원 해석·금액 정합을 명시
  - **빠른 피드백**: 단위 테스트라 CI 부담 낮음
  - **회귀 고정**: 두 결함이 재발하면 즉시 실패

---

## 검증 결과
- **전체 백엔드 테스트 그린** (JDK23 + H2/Testcontainers, `BUILD SUCCESSFUL`). 신규 7케이스 포함 회귀 없음.
- main은 분기 후 미전진 → 병합 충돌 없음.

## 코드로 고치지 않고 남긴 것 (의도·운영 사안)
| 항목 | 판단 |
|---|---|
| `/actuator/**` permitAll + dev JWT 기본 시크릿 | 코드 결함 아님. **배포 체크리스트**(IP 제한·`JWT_SECRET` 주입) — 코드 주석에도 경고 존재 |
| 정산·리더보드 조회의 참여자 무관 접근 | PUBLIC 챌린지 정책이면 정상 — **제품 판단** 필요, 임의 변경은 회귀 위험 |
| 개인 체크인 best-effort 흡수 | 축 격리 설계 의도(`CheckInOrchestrator` try/catch). 동작 확인만 권장 |
| `BAxisIsolationTest`가 `social` 미포함 | A-1이 isolation 위반이 아닌 신원 버그라 해당 테스트 대상 아님. cheer 단위 테스트로 커버 |

## 관통 주제
- **A·B** = "신원과 금액은 서버가 원자적으로 확정한다" — JWT userId를 참여자로 해석해 위조 차단(A), 검사→차감의 TOCTOU를 락 **대상**이 아니라 **임계영역**을 넓혀(검사를 락 안으로) 막아 무발행 차단(B).
- **C·D** = "계약과 오류는 명확하게" — 죽은 포트 제거로 통합 표면 축소(D), 잘못된 인자는 4xx로 표준화(C).
- **E** = "발견한 결함은 테스트로 고정한다" — H2 프로파일이 놓친 제약을 서비스 단위 테스트가 대체 검증.
