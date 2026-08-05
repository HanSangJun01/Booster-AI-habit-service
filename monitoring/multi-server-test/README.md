# 멀티서버 테스트 (Docker 기반)

실제 3인스턴스 스택(nginx LB + backend 3대 + 공유 DB)에서 멀티서버 정합성/가용성을
**재현 가능하게** 자동 검증한다. 두 종류:

1. **P1 (정산 이중지급 방지)** — 스케줄러가 여러 인스턴스에서 동시에 발화해도 코인 이중지급 없음
2. **Failover (무중단)** — 한 인스턴스가 중지돼도 나머지가 대신 서빙(zero-downtime)

> 원칙: **Spring 메인 코드(`src/main/**`)는 절대 수정하지 않는다.** 이 디렉터리는
> 테스트용 데이터(SQL)와 오케스트레이션(bash)만 담는다.

## 구성

| 파일 | 역할 |
|---|---|
| `p1-settlement-seed.sql` | 실제 `users` 를 갖춘 ENDED 챌린지 20개 시드. A팀 전원 SUCCESS·B팀 무체크인 → A팀 승리 확정. 정산 성공(COMPLETED) 조건을 만든다. 재실행 가능(MST 데이터 선정리). |
| `run-p1-test.sh` | (P1) 멀티 스택 기동 → 시드 → **3대 동시 재시작** → 정산 완료 폴링 → P1 불변식 검증(PASS/FAIL). |
| `run-failover-test.sh` | (Failover) 기준선 분산 확인 → **backend-1 중지** → 무중단·죽은대 축출·생존대 서빙 검증 → 재기동 → 재편입 확인. 데이터 시드 불필요(`/actuator/health` 만 사용). |

## 왜 전용 시드가 필요한가

기존 `b-axis-seed-saturation.sql` 은 **읽기 부하테스트**용이라 참여자에 합성
`user_id`(1,000,000+, `users` 행 없음)를 쓴다. 리더보드 조회는 `users` 를 안 보므로 문제없지만,
정산은 코인 지급 시 `users` 를 조회하므로 "사용자 없음"으로 전부 FAILED 된다. 이 테스트는
정산이 실제로 **COMPLETED** 되어야 "이중지급 여부"를 코인 잔액으로 검증할 수 있으므로,
실제 `users` 행(200명, id 2000001..2000200)을 심는다.

## 실행

```bash
# 사전: docker 데몬 실행 중
bash monitoring/multi-server-test/run-p1-test.sh         # P1(정산 이중지급 방지)
bash monitoring/multi-server-test/run-failover-test.sh   # Failover(무중단)
# 종료코드 0 = 전체 통과, >0 = 실패 개수
```

스택만 따로 올리려면:
```bash
docker compose -f docker-compose.multi.yml up -d --build
```

## 데이터 형상 & 기대값

- 20 ENDED 챌린지 × (2팀 × 5명) = **200 참여자 = 200 실제 유저**
- deposit 1000, 참여자 10명 → `totalPool = 1000 × 10 = 10000`
- A팀 승리 → 승자 5명이 5등분 → **1인당 2000 코인**
- 기대: 정산 20건 COMPLETED, 승자 100명 잔액 2000, 패자 100명 잔액 0, 총지급 200000

## 검증하는 P1 불변식

1. **정산 성공** — MST 정산 20건 전부 COMPLETED (FAILED 0)
2. **이중정산 없음** — challenge당 settlement 1행 (중복 0)
3. **이중지급 없음(핵심)** — 승자 잔액이 **정확히 2000** (두 번 지급되면 4000+). 비정상 잔액 0
4. **거래 일관성** — `SETTLEMENT_WIN` 거래 100건, 합계 200000
5. **ShedLock 직렬화** — 3대 동시 발화에도 정산 본문을 실행한 인스턴스는 **1대**

## 검증하는 Failover 불변식

1. **기준선** — 3대가 모두 트래픽을 받음(서빙 인스턴스 3)
2. **무중단** — backend-1 중지 중에도 요청 성공률 100%
3. **죽은대 격리** — 중지된 인스턴스가 서빙한 요청 0건
4. **생존대 서빙** — 남은 2대로만 라우팅(서빙 인스턴스 2)
5. **자동 재편입** — 재기동 후 다시 3대에 분산(서빙 인스턴스 3)

> nginx `max_fails=3 fail_timeout=5s` 설정이 죽은 업스트림을 감지·축출하고, 재시도 체인
> (죽은IP→산IP)으로 클라이언트에는 무중단으로 보이게 한다.

## 동작 원리 (P1 방어 계층)

- **ShedLock**: 공유 DB `shedlock` 테이블 락 → 동시에 한 인스턴스만 스케줄러 본문 실행
- **`settlements.challenge_id` UNIQUE**: 두 정산이 겹쳐도 INSERT 하나만 성공(나머지 skip)
- **FAILED→PENDING CAS**: 재시도 경로에서도 한 호출자만 소유권 획득

세 계층이 함께 "정확히 1회 정산 / 이중지급 없음"을 보장한다. 이 테스트는 **3대를 동시
재시작**해 셋이 같은 순간 `retryFailedSettlements` 를 발화시켜(최대 동시 경쟁) 이를 실증한다.
