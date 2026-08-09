# 멀티 서버 환경 고려사항

> 현재 서버 1대 기준으로 운영 중. 스케일아웃 전에 아래 항목을 반드시 해결해야 함.
> 작성일: 2026-07-01 · 브랜치: `test/BS-30-backend-validation-b-axis`

---

## 1. 스케줄러 중복 실행 (위험도: 매우 높음)

**위치**: `ChallengeEndScheduler.java`

**문제**
`@Scheduled`는 서버마다 독립적으로 실행돼. 서버가 2대면 60초마다 2번 정산이 트리거됨.

```
서버A → markEndedChallenges() → 챌린지1 정산 시작
서버B → markEndedChallenges() → 챌린지1 정산 시작 (동시에)
→ 코인 이중 지급 위험
```

현재 D-1의 PENDING 선점 + 유니크 제약이 어느 정도 막아주지만, 정산 계산이 시작된 후 PENDING 저장 전 구간에서 동시 진입 가능성이 있음.

`retryFailedSettlements()` (5분 주기)도 동일한 문제.

**해결책**
- **ShedLock** 도입: `@SchedulerLock`으로 분산 환경에서 하나의 인스턴스만 실행 보장
- 또는 **Quartz 클러스터 모드**: DB 기반 작업 예약으로 중복 실행 원천 차단

---

## 2. 팀 구성 비결정적 셔플 (위험도: 높음)

**위치**: `TeamFormationService.java:53`

**문제**
```java
Collections.shuffle(shuffled) // 서버마다 다른 랜덤 순서
```
두 서버가 동시에 팀 구성을 시도하면 A팀/B팀 멤버가 달라짐. DB 유니크 제약이 하나를 막지만, 그 전에 참가자 배정이 꼬일 수 있음.

**해결책**
- `Collections.shuffle()` 제거
- `participant_id` 오름차순 정렬 후 앞 5명 A팀, 뒤 5명 B팀으로 **결정적 배정**
- 어느 서버가 실행해도 동일한 결과 보장

---

## 3. 참여율 업데이트 Lost Update (위험도: 중간)

**위치**: `ChallengeCheckInService.updateTeamParticipationRate()`

**문제**
```
서버A: 참여율 60% 계산 → 저장 중
서버B: 참여율 80% 계산 → 저장
서버A: 60%로 덮어씀 → 서버B 업데이트 유실
```
Team row에 락이 없어서 마지막으로 저장한 값이 이김.

**해결책**
- Team 엔티티에 `@Version` 필드 추가 (낙관적 락)
- 충돌 시 재시도 처리
- 또는 Team row에 PESSIMISTIC_WRITE 락

---

## 4. 정산 멱등 게이트 경쟁 구간 (위험도: 낮음)

**위치**: `SettlementService.java:54-72`

**문제**
```
서버A: settlement 없음 확인 ──┐
서버B: settlement 없음 확인 ──┘ (동시)
→ 둘 다 PENDING 저장 시도
→ 유니크 제약이 하나 거부 (현재 방어됨)
```
현재 `DataIntegrityViolationException` catch로 처리하고 있어 실질적 위험은 낮음. 다만 정산 계산 로직이 두 서버에서 동시에 시작되는 짧은 구간은 존재.

**해결책**
- Challenge row에 PESSIMISTIC_WRITE 락 추가 (정산 시작 시점)
- 락 잡은 후 PENDING 저장 → 완전한 직렬화

---

## 5. 참가자 수 카운트 경쟁 (위험도: 낮음)

**위치**: `ParticipationService.java:50-52`

**문제**
Challenge row에 PESSIMISTIC_WRITE 락을 잡지만, 참가자 수 카운트 쿼리는 락 밖에서 실행될 수 있음. 서버가 여러 대면 동시에 9명을 보고 둘 다 승인할 가능성.

**해결책**
- 카운트 쿼리를 락 획득 이후로 이동
- 또는 `countByChallengeIdAndStatus()` 쿼리에 락 적용

---

## 우선순위 및 작업 순서

| 순위 | 항목 | 이유 |
|---|---|---|
| 1 | 스케줄러 중복 (ShedLock) | 코인 이중 지급 → 직접적 금전 손실 |
| 2 | 팀 구성 셔플 제거 | 정산 결과 정합성 깨짐 |
| 3 | 참여율 낙관적 락 | 데이터 유실, 사용자 불신 |
| 4 | 정산 Challenge 락 | 현재 유니크 제약으로 대부분 커버 |
| 5 | 참가자 수 카운트 락 | 현재 단일 서버라 실질 위험 낮음 |

---

## 참고

- 현재 DB 유니크 제약(정산, 팀 구성, 체크인)이 최후 방어선 역할을 하고 있어 서버 1대 환경에서는 안전함
- 스케일아웃 결정 시 **1번(ShedLock)을 가장 먼저** 적용할 것
- ShedLock 의존성: `net.javacrumbs.shedlock:shedlock-spring`, `shedlock-provider-jdbc-template`
