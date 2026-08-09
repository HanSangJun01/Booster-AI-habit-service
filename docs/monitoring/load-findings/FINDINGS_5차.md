# A×B 통합면 버그/성능 측정 보고서 — 5차 (integration/a-b-axis)

> 1~4차는 **A축 단독**을 봤고([BUGS-총정리표](../summary/BUGS-총정리표.md) 기준 22개 수정 후 수렴), B축은 `b-axis-run-scenarios.sh`/`b-axis-saturation.js`가 따로 봤다.
> **두 축이 만나는 지점은 아무도 안 봤다** — 이 보고서는 그 통합면만 본다.
> 측정일: 2026-07-15 · 브랜치 `integration/a-b-axis` (`2076533`)

## 조치 현황 (2026-07-24 업데이트)
발견 **13건**(1차 프로브 I1~I9 + 2차 프로브 I10~I13) 중 **코드 버그 9건 수정 완료 + 테스트 + 재프로브로 BUG→OK 확인**.

| ID | 상태 | 재검증 |
|----|------|--------|
| I10 LEADER PENDING 취소 보증금 증발 | ✅ 수정 | 프로브2 Q1: 취소 후 코인 400→**500 환불**. 유닛테스트 추가 |
| I11 leaderboard 필수파라미터 500 | ✅ 수정 | 프로브2 Q3: type 누락 → **400** |
| I13 동시 취소 이중 환불(코인 파밍) | ✅ 수정 | 프로브2 Q2: 3회 연속 **환불 1회**. `findByIdWithLock`로 직렬화 |
| I12 응원 무한 중복 | ⏸️ 결정대기 | "응원=리액션"이면 정상. dedup 필요 여부 팀 결정 |

아래는 1차 프로브(I1~I9) 조치 현황.

| ID | 상태 | 재검증 |
|----|------|--------|
| I1 B축 동시 체크인 500 | ✅ 수정 | contention 재실행: `AssertionFailure` 10→**0**, 5xx **0**, UNIQUE위반 11건은 멱등 처리됨. 유닛테스트 추가 |
| I2 남의 팀 채팅 열람 | ✅ 수정 | 프로브 P3: 비참여자 조회 **403** |
| I3 자기응원 무력화 | ✅ 수정 | 프로브 P6: participant_id 자기응원 **400** |
| I4 응원 500 | ✅ 수정 | 프로브 P6: userId로 응원 → 500 아닌 **400** |
| I5 size 무제한 | ✅ 수정 | 프로브 P4: `size=1000000` → 반환 size **100**(양 엔드포인트) |
| I6 채팅 길이 무제한 | ✅ 수정 | 프로브 P5: 10만자 → **400** |
| I7 코인 조용한 증발 | ⏸️ 결정대기 | 의도된 설계(§I7). 실패 시 정책(동반실패/재시도/알림)을 팀이 정해야 함 |
| I8 actuator 공개 | 📄 배포설정 | 코드 아님. EC2에서 IP 제한(§I8) |
| I9 정산 유실 | ⏸️ 결정대기 | 시드 유발. FK·정산 원자성은 돈 관련이라 상의 후(§I9) |

**수정 파일**: `CheckInInsertHelper`/`ChallengeCheckInService`(I1), `TeamChatService`/`SocialController`(I2/I3), `CheerService`(I3/I4), `GlobalExceptionHandler`(I4), `application.yml`(I5), `SendMessageRequest`(I6). 전체 테스트 GREEN(Testcontainers 포함).

## 측정 환경
- Docker Compose: PostgreSQL 16 + Spring Boot (백엔드 8080), HikariCP max=30
- 볼륨 시드: `b-axis-seed-saturation.sql` → **챌린지 513 / 참여자 5,048 / 체크인 102,003 / 팀 1,008**
- 도구 (이번에 신규 작성):
  - `monitoring/scripts/probe-integration.sh` — 논리 버그를 한 방씩 찌르는 프로브 (부하 아님)
  - `monitoring/k6/integration-realistic.js` — `SCENARIO=journey|search|teamdetail|contention` 통합 부하

---

## 🔴 핵심 발견 — I1: B축 동시 체크인이 500 (A축에서 고친 버그가 B축에 그대로 남음)

같은 유저가 챌린지 체크인을 동시에 보내면 **HTTP 500**. 측정 중 **10회 발생**.

```
ERROR: duplicate key value violates unique constraint "unique_participant_date"  (SQLState 23505)
  ↓
org.hibernate.AssertionFailure: null id in ChallengeCheckIn entry
  (don't flush the Session after an exception occurs)
```

**원인** — `CheckInInsertHelper.insertOrFetch` (REQUIRES_NEW):

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public ChallengeCheckIn insertOrFetch(...) {
    try {
        return checkInRepository.save(newCheckIn);
    } catch (DataIntegrityViolationException e) {
        // REQUIRES_NEW 트랜잭션 안에서 rollback됨 — 바깥 트랜잭션은 오염되지 않음  ← 이 주석이 틀렸다
        return checkInRepository.findByParticipantIdAndCheckInDate(participantId, date)
                .orElseThrow(...);
    }
}
```

주석의 주장과 달리, **catch 가 REQUIRES_NEW 경계 *안*에서 일어나므로 그 시점엔 아직 롤백되지 않았다.**
`save()` 가 제약조건을 때린 순간 Hibernate 세션은 이미 오염되고(실패한 엔티티가 id=null 로 영속성 컨텍스트에 잔류),
같은 세션으로 `findBy...` 를 호출하면 flush 가 걸려 `AssertionFailure` 로 터진다.
→ 바깥 트랜잭션이 아니라 **자기 자신의 세션**이 오염되는 게 문제다.

**같은 계열이 A축엔 이미 고쳐져 있다.** [BUGS-총정리표](../summary/BUGS-총정리표.md) `C4: 같은날 동시 첫인증 → 500` → `DataIntegrityViolation → 409` 로 수정 완료.
B축 챌린지 체크인만 그 수정을 못 받았다.

**수정 방향** — 예외를 REQUIRES_NEW 메서드 **밖으로 던져** 내부 트랜잭션이 실제로 롤백되고 세션이 폐기되게 한 뒤,
**호출자에서 잡아** 새 트랜잭션으로 조회한다. (insert 시도와 fetch 를 서로 다른 트랜잭션으로 분리)

---

## 🔴 I2: 남의 팀 채팅이 다 읽힌다 (멤버십 검사 없음)

| 요청 | 결과 |
|---|---|
| 비참여자가 `GET /api/teams/{teamId}/chat` | **200 — 전문 조회됨** |
| 비참여자가 `POST /api/teams/{teamId}/chat` | 403 (차단됨) |

쓰기에는 멤버십 검사가 있는데(`TeamChatService.sendMessage`) **읽기에만 없다.** 로그인만 하면 임의의 `teamId` 로 남의 팀 대화를 통째로 읽는다.

---

## 🟡 I3~I8 (전부 재현 확인)

| ID | 문제 | 증거 | 비고 |
|----|------|------|------|
| I3 | **자기응원 가드 무력화** | 자기 `participant_id` 로 응원 → **201** | `SocialController:67` 이 `@AuthenticationPrincipal Long fromParticipantId` 로 **userId** 를 받아 participantId 자리에 씀. `CheerService` 의 `fromParticipantId.equals(toParticipantId)` 가 서로 다른 ID 공간을 비교 → 항상 통과. `toParticipantId` 의 실존/소속 검증도 없음 |
| I4 | **응원 500** | userId 로 보내면 **500** | `IllegalArgumentException` 미매핑. 400 이어야 함 |
| I5 | **페이지 사이즈 무제한** | `GET /api/challenges?size=1000000` → **200**<br>`GET /teams/{id}/chat?size=1000000` → **200** | A축 코인내역은 F9 수정으로 [1,100] 클램프. B축은 raw `Pageable` 이라 무방비 |
| I6 | **채팅 본문 길이 무제한** | 10만자 → **201 저장됨** | `SendMessageRequest.content` 에 `@Size` 없음 |
| I7 | **A/B축 조용한 어긋남** | B축 체크인 **201** + A축 개인체크인 **0건** | `CheckInOrchestrator` 가 A축 실패를 try/catch 로 삼킴(WARN 로그만). 설계 의도이나 **코인 보상이 말없이 증발**하고 재시도/보정 경로가 없음 |
| I8 | **actuator 무인증 공개** | `/actuator/prometheus` → **200**<br>`/actuator/health` 상세 노출 | `SecurityConfig` permitAll. 코드 주석도 "EC2 에선 IP 제한 필요"로 인지 중 |

---

## 🟡 I9: 정산 실패 시 재시도도 기록도 없다 + `challenge_participants.user_id` 에 FK 없음

측정 중 `Settlement failed for challengeId=17` 1회.

- **직접 원인은 시드 아티팩트다** — `b-axis-seed-saturation.sql` 이 합성 `user_id`(1,000,000+)를 쓰는데 `users` 에 그 행이 없어 `CoinService.lockUser` 가 `사용자를 찾을 수 없습니다` 로 던짐. **제품 트래픽이 만든 버그가 아니다.**
- **그런데 드러난 구멍은 진짜다:**
  1. `challenge_participants.user_id` 에 **FK 가 없다** (`pg_constraint` 조회로 확인). DB 가 "참여자의 유저가 실존한다"를 보장하지 않는다.
  2. `SettlementService.settleChallenge` 는 참여자 최대 10명에게 코인을 **루프로 지급**한다. **한 명이 없으면 예외 → 트랜잭션 통째 롤백 → 그 챌린지 전원 미정산.**
  3. 이번 실행 결과: 챌린지는 `ENDED` 로 **넘어갔고**, `settlements` 테이블은 **0행**. 스케줄러는 `findByStatusAndEndedAtBefore` 로 집으므로 이미 `ENDED` 인 이 챌린지를 **다시 집지 않는다** → **재시도 없음, 실패 기록 없음, 영구 미정산.**

상태 전이는 커밋되고 정산만 유실되는 이 조합은 시드와 무관하게 위험하다.

---

## 🔴 2차 프로브(돈·동시성·엣지) 신규 발견 — I10~I12

`probe-integration2.sh`로 참가비(deposit) 흐름과 동시성을 찔러 **신규 3건**. 함께 **2건은 정상 확인**.

### 🔴 I10: LEADER 승인형에서 PENDING 참여자가 취소하면 보증금이 증발한다
- 재현: LEADER 승인형 챌린지 참여 → 코인 500→400(차감) → 상태 **PENDING** → 취소(200) → 코인 **400 그대로**(환불 안 됨).
- 원인(`ParticipationService`): 참여 시 `coinService.deduct`는 **무조건**(line 58) 실행되는데, 취소 환불 `coinService.credit`는 **`status == CONFIRMED`일 때만**(line 135). AUTO형은 즉시 CONFIRMED라 환불되지만, **LEADER형은 참여 직후 PENDING**이라 취소해도 환불 경로를 안 탄다.
- 파급: 승인 대기 중 마음 바뀌어 취소한 유저가 **보증금을 통째로 잃는다.** 승인받지 못한 채 챌린지가 시작돼도(취소는 READY에서만 가능) 그 보증금은 어디에도 환불되지 않는다. **돈이 새는 버그.**
- 수정 방향: 취소 환불 조건을 "코인이 실제 차감된 상태"로 넓힌다 — 즉 PENDING/CONFIRMED 모두 환불(참여 시 무조건 차감했으므로). CANCELLED 재취소만 배제.

### 🔴 I11: 리더보드 필수 파라미터 누락 시 500 (400이어야)
- 재현: `GET /api/challenges/{id}/leaderboards` (필수 `?type` 없이) → **500**.
- 원인: `MissingServletRequestParameterException`이 `GlobalExceptionHandler`에 미매핑 → `handleGeneral`(500). F9(타입불일치)·I4(IllegalArgument)와 **같은 계열**.
- 수정 방향: `MissingServletRequestParameterException → 400` 핸들러 추가.

### 🟡 I12: 응원 무한 중복 (dedup/rate-limit 없음)
- 재현: 같은 `from→to`로 응원 5연타 → 5행 모두 201 저장.
- 성격: 유니크 제약·레이트리밋 없음. **다만 "응원=리액션"으로 여러 번 허용이 의도일 수 있어** 제품 결정 사항(리액션형이면 정상, 카운트형이면 dedup 필요).

### 🔴 I13: CONFIRMED 참여자 동시 취소 → 이중 환불(코인 파밍)
- 재현: CONFIRMED 참여자(코인 500→400)에 취소 8발 **동시** 발사 → 코인 **400→600**, 환불성 거래 **2건**. 취소는 한 번인데 환불이 여러 번 → **코인이 무에서 생성**된다.
- 성격: **타이밍 의존(flaky).** 1차 프로브 실행에선 안 걸렸고 재실행에서 재현됨. 즉 조건이 맞으면 언제든 터진다.
- 원인(`ParticipationService.cancelParticipation`): 챌린지를 `findById`(**무락**)로 읽어 동시 취소가 직렬화되지 않았다. 두 요청이 각각 `status=CONFIRMED`를 읽고 각자 환불. (참여 `requestParticipation`은 `findByIdWithLock`으로 잠그는데 취소만 안 잠갔다 — 비대칭.)
- 수정: 취소도 `findByIdWithLock`으로 챌린지 비관락 → 먼저 취소한 트랜잭션이 상태를 CANCELLED로 커밋한 뒤에야 다음 취소가 진입, 재환불 안 함.

### ✅ 함께 확인된 정상 (버그 아님)
- **정원 초과 동시 참여(Q4): 정상.** max=10 챌린지에 12명 동시 참여 → CONFIRMED 정확히 **10**. `findByIdWithLock`(Challenge 비관락)이 참여 경쟁을 직렬화.

---

## 성능 — 엔드포인트별 결과

### journey (A축 6종 + B축 8종 순회, 0→50 VU, think-time 1s)
**전 엔드포인트 23~28ms 로 평평. 병목 없음.** 35,662요청 / 282 rps / 실패 0.01%.

| 엔드포인트 | p95 | | 엔드포인트 | p95 |
|---|--:|---|---|--:|
| B:challenge-list | 27.9ms | | B:challenge-detail | 25.6ms |
| A:coins | 27.3ms | | B:teams | 25.4ms |
| A:dashboard | 27.1ms | | B:leaderboard-team | 25.3ms |
| B:checkin-list | 26.3ms | | A:recovery | 24.2ms |
| A:checkin-today | 26.3ms | | B:chat | 24.1ms |
| B:leaderboard-personal | 25.8ms | | A:me | 23.8ms |
| A:location | 25.7ms | | B:team-detail | 23.4ms |

축별: A축 p95 25.9ms / B축 p95 25.5ms — **두 축 차이 없음.**

### 부하를 높인 격리 시나리오

| 시나리오 | 조건 | p95 | p99 | max | rps |
|---|---|--:|--:|--:|--:|
| **teamdetail** | 150 VU, think-time 0 | **228ms** | **584ms** | 1.0s | 602 |
| **search** | 80 VU, think-time 0, 매칭0건 키워드 | **113ms** | **288ms** | (26.7s ※) | 377 |
| **contention** | 30 VU, A축·B축 체크인 동시 | 10~13ms | 37~43ms | 221ms | 114 |

※ `max=26.7s` 와 실패 8~9건은 **전부 `dial: i/o timeout`** — k6 컨테이너가 `host.docker.internal` 로 TCP 연결 자체를 못 뺀 것.
Docker Desktop(Windows) 포트포워딩 아티팩트지 **서버 지연이 아니다.** 서버 지연으로 읽으면 안 된다.

### 서버측 관측
- **HikariCP: active 0~2, idle 17, pending 0** — 50 VU 에선 풀이 병목이 아니다. 풀 30 은 이 부하엔 과하다.
- **슬로우쿼리(>100ms) 로그: 0건.**
- **데드락/락타임아웃: 0건** → "A축은 User 락만, B축 참여는 Challenge→User 순, 정산은 User 10개 루프라 락 순서 충돌로 데드락이 날 것"이라는 **가설은 기각.**
- 쿼리 실측:
  - 최악 검색(`LIKE '%nomatch%'`) → **Seq Scan 확정**(인덱스 못 탐), 그러나 516행이라 **0.3ms**
  - 리더보드 GROUP BY(102k 체크인 위) → `idx_participants_challenge_id` 타고 840행 → **1.1ms**. N+1 은 이미 제거돼 있음

### 🔧 개선 후보
| 항목 | 근거 | 판단 |
|---|---|---|
| `team-detail` 캐시키 | `challengeId_userId` 라 참여자 수만큼 엔트리가 갈림. 150 VU 에서 p99 584ms 로 읽기 중 최악 | **유일한 실질 후보.** 팀 단위 캐시키(`challengeId_teamId`)로 바꾸면 엔트리가 1/5로 줄어든다 |
| `GET /api/challenges` LIKE %kw% | Seq Scan 확정이나 516행에선 0.3ms | **지금은 아님.** 챌린지가 수만~수십만 되면 아픔 → trigram 인덱스(`pg_trgm`)나 검색 분리는 그때 |
| HikariCP 30 | pending 0, active 0~2 | **줄일 여지는 있으나 실익 없음.** 그대로 둔다 |
| `TeamChatService.sendMessage` 멤버십 N+1 | 메시지마다 참여자 전원 로드 | 팀당 5명이라 현재 무해. I2(읽기 권한) 고칠 때 같이 정리 |

---

## 측정의 한계 (다음 차수에서 보완할 것)
1. **journey 는 볼륨을 타지 않는다.** `setup()` 이 자기 챌린지를 새로 만들어 읽으므로, team-detail·리더보드·체크인목록 수치는 **참여자 10명짜리 소량 데이터 기준**이다. 시드한 102k 체크인을 실제로 타는 건 `challenge-list` 와 `search` 둘뿐.
2. **원인**: `b-axis-seed-saturation.sql` 의 참여자는 합성 `user_id`(1,000,000+)라 **로그인이 안 돼** JWT 로 그 챌린지를 읽을 수 없다. 대용량 챌린지를 JWT 로 읽으려면 `b-axis-seed-team-detail.sql` 처럼 **실유저 앵커**를 만드는 방식이 필요하다.
3. 따라서 **"통합면에 성능 병목이 없다"는 결론은 이번 데이터 형태 한정**이다. team-detail p99 584ms 도 소량 챌린지 기준이라, 깊은 히스토리 위에서 다시 재야 한다.

---

## 5차 결론
- **성능: 통합면에 병목 없음.** 전 엔드포인트 23~28ms, 풀 여유, 슬로우쿼리 0, 데드락 0. 개선 후보는 `team-detail` 캐시키 **1건뿐**. (단 위 "한계" 3항 전제)
- **정합성: 코인은 튼튼하다.** 참가비 차감 정확, 잔액 100에 100짜리 2개 동시 신청해도 음수 안 됨 — A축 하드닝(C1/C5 User 비관락)이 B축까지 지켜준다.
- **버그는 성능이 아니라 통합면의 권한·검증·예외처리에 몰려 있다.** 총 **9건 재현**, 그중 🔴 2건:
  - **I1 B축 동시 체크인 500** — A축이 이미 고친 버그(C4)를 B축이 못 받음
  - **I2 남의 팀 채팅 열람** — 읽기에만 멤버십 검사 누락
- **패턴**: A축은 4차까지 두들겨 맞아 단단해졌는데, **B축은 같은 종류의 검사(클램프·길이제한·권한·예외매핑)를 아직 안 받았다.** A축 총정리표의 F9/F11/C4/F4 를 B축에 그대로 대입해보는 게 다음 작업으로 가장 값싸고 수확이 크다.
