# Booster 프로젝트 계획서

> **이 문서가 제품 기준선이다.** `integration/a-b-axis` 브랜치의 실제 구현을 기준으로 쓰였고,
> 다른 파트(프론트·AI)는 이 문서 하나에 맞춘다. 화면은 §10, API 계약은 §11에 있다.
>
> 최종 갱신: 2026-08-27 · 기준 커밋: `integration/a-b-axis` (V16 마이그레이션)
>
> 이전 판(2026-05 deep-interview 기반)은 **복귀 미션 모델**을 전제로 쓰였으나 그 모델은 폐지됐다.
> 무엇이 왜 바뀌었는지는 §9 변경 이력 참조.
>
> ### ⚠️ main 의 코드는 아직 이 문서와 다릅니다
>
> 이 문서는 **`integration/a-b-axis` 브랜치의 코드**를 설명한다. `main` 은 아직 V9 시점이라
> 복귀 미션 테이블·코드가 남아 있다. **코드를 볼 때는 `integration/a-b-axis` 를 보라.**
>
> 문서를 먼저 올린 이유는, 각 파트가 이 기준에 맞춰 작업을 시작할 수 있게 하기 위해서다.
> 코드 병합은 별도로 진행한다.

---

## 📌 여기부터 보세요 — 파트별 시작점

전체를 다 읽을 필요 없다. **자기 파트 항목만 보고 시작하면 된다.**

### 🔴 프론트 — 총 10건 (P0 3 · P1 4 · P2 3)

> ⚠️ **P0 3건만 고치면 끝이 아니다.**
> P0은 "지금 앱이 깨져 있는 것"이고, **P1·P2가 "서버와 어긋난 것"**이다.
> 토요일에 합칠 때 실제로 문제가 되는 건 대부분 **P2**다 — 값과 문구가 서버와 다르면
> 화면은 뜨는데 동작이 틀린다.

**🔥 P0 — 지금 깨져 있다** (앱이 404를 받는 중)

| # | 할 일 | 상세 |
|---|---|---|
| 1 | `recovery_service.dart` · `models/recovery.dart` **삭제** + 호출부 제거 | §12 |
| 2 | **상점을 서버 API로** — 구제권 구매는 이미 서버에 있다. 가격 100 ❌ → **800** ⭕. "사용" 버튼 제거 | **§S-6** (체크리스트 8개) |
| 3 | **구제 안내 팝업** — 없으면 사용자가 새벽에 예고 없이 스트릭 0 + 코인 −500 | **§S-8.4** |

**📌 P1 — 서버에 있는데 화면이 없다**

| # | 할 일 | 상세 |
|---|---|---|
| 4 | **주간 목표 화면** — A축 핵심(목표·진행률·구제권)인데 볼 방법이 없다 | §S-8.1 |
| 5 | **AI 사진 업로드** — 없으면 개인·팀 모두 AI 인증을 못 쓴다 | §S-5.4 |
| 6 | 참여 챌린지를 서버에서 복원 (현재 로컬 보관 → 재설치 시 유실) | §S-4.1 |
| 7 | **방장 승인 화면** — `LEADER` 승인 챌린지가 작동 불가 | §S-4.5 |

**🔧 P2 — 값·문구가 서버와 어긋난다** ← *합칠 때 제일 많이 부딪히는 부분*

| # | 할 일 | 상세 |
|---|---|---|
| 8 | **카테고리를 영문으로** — 지금 한글(`운동`)을 보내서 **AI 인증이 전부 실패**한다. 운동→`EXERCISE`, 공부·독서→`STUDY`, 기상은 AI 제외 | §4.1 |
| 9 | 챌린지 생성 — 정원 입력 제거(**10 고정**) · 인증 방식 3종 제한 · **GPS 좌표 필수** | §S-4.3 |
| 10 | 스트릭 문구 "7일 연속" → **"7회마다"** (연속 일수가 아니라 누적 횟수) | §3.6 |

> 응답 형태가 축마다 다르다 — A축은 raw JSON, B축은 `{success, data}` 래핑 (§A-1.2).
> 통일은 별도 과제이니 **파싱만 분기**해두면 된다.

화면 단위 상세·37개 API 매핑은 **§10 화면 명세**, 전체 체크리스트는 **§12** 에 있다.

### 🟢 AI — 이번에 고칠 코드 없음

카테고리는 `EXERCISE`/`STUDY` 2개 유지로 확정(§4.1). 계약도 그대로다.
확인만 두 가지 → §12 · `docs/api/AI_SERVICE_SPEC.md` §8.6·§8.7

### 🟡 백엔드 · 인프라

미해결 4건 (분산락 · 구제 만료 멱등성 · GPS 반경 상한 · 카테고리 검증) → §12

---

> **토요일 전까지의 목표**: 위 항목을 다 끝내는 게 아니라, **각 파트가 이 문서와 어긋난 곳을
> 없애 두는 것**이다. 그래야 그날은 합치는 작업만 하면 된다.
> 시간이 부족하면 **P0 → P2 → P1 순서**를 권한다 — P2가 값·문구 수정이라 가장 싸고,
> 안 맞추면 합칠 때 바로 부딪힌다.

---

## 1. 제품 개요

Booster는 **습관 형성 서비스**이고, 두 축으로 나뉜다.

| 축 | 무엇 | 판정 단위 | 실패 대가 |
|---|---|---|---|
| **A축 — 개인 습관** | 혼자 하는 습관. 주 N회 목표를 세우고 인증한다 | **주 1회** (매주 월 00:01) | 스트릭 초기화 + 코인 차감 |
| **B축 — 팀 챌린지** | 10명이 5:5로 나뉘어 참여율을 겨룬다 | 챌린지 종료 시 | 예치금 소멸 |

두 축은 **같은 코인 지갑과 같은 사용자 계정**을 쓰지만, 인증 기록·판정·스트릭은 완전히 분리돼 있다.
팀 챌린지 인증은 개인 스트릭을 올리지 않고, 개인 인증은 팀 참여율에 들어가지 않는다.

**기술 스택**

- 모바일: Flutter (iOS/Android)
- 백엔드: Spring Boot REST API + PostgreSQL (Flyway V1~V16)
- AI 인증: FastAPI + Claude Vision (`ai-service`, opt-in 프로필)
- 모니터링: Prometheus + Grafana + postgres_exporter

---

## 2. MVP 범위

### 구현 완료

| 컴포넌트 | 핵심 기능 |
|---|---|
| **Auth & User** | 이메일+비밀번호 가입/로그인, 가입 응답에 토큰 포함, 마이페이지, 회원 탈퇴(soft delete), 코인 내역 |
| **A축 개인 습관** | 인증 위치 등록, 일일 인증(GPS/AI/GPS+AI), **주간 목표(주 2~7회)**, **구제권**, **구제 유예**, 스트릭, 마일스톤 보상 |
| **B축 팀 챌린지** | 챌린지 생성/탐색/참여, 정원 10명 충족 시 5:5 자동 편성 + 자동 시작, 일일 인증, 팀 상세, 채팅·응원, 리더보드, 종료 정산 |
| **AI 사진 인증** | 개인·팀 양쪽. 체크인 PENDING → 사진 업로드로 확정 |
| **상점** | 구제권 판매 (§6) |
| **Home Dashboard** | 코인·스트릭·이번 주 성공 횟수·캘린더 |
| **운영** | ShedLock 분산락(정산), 멀티 인스턴스 구성, Actuator 계기판 |

### Phase 2 (미구현)

| 항목 | 사유 |
|---|---|
| 푸시 알림 | 인프라(FCM) 별도 |
| 기프티콘 판매 | 재고·발급 연동 필요 (§6.3) |
| 소셜 로그인 / 이메일 인증 / 비밀번호 재설정 | MVP 단순화 |
| 코인 충전·결제 | 결제 연동 제외 |
| 알림 설정 / 사용자 설정 | 테이블·API 없음 |
| 챌린지 나가기 | 회원 탈퇴 예외만 처리 |

---

## 3. A축 — 개인 습관 (주간 목표 모델)

### 3.1 왜 '주' 단위인가

이전 모델은 **매일 인증**을 전제로 했다. 하루라도 빠지면 복귀 미션이 뜨고, 스트릭은 연속 일수였다.
여기에 "주 N회 목표"를 넣으면 모순이 생긴다 — 주 3회 사용자는 월·수·금 사이의 갭 때문에
**스트릭이 영원히 1**이고, **쉬는 게 정상인 날마다 복귀 미션이 발동**한다.

그래서 판정 단위를 일 → 주로 올렸다.

| | 이전 (복귀 미션) | **현재 (주간 목표)** |
|---|---|---|
| 판정 주기 | 매일 00:01 | **매주 월 00:01** |
| 발동 조건 | 어제 인증 안 함 | **지난주 목표 미달** |
| 만회 방법 | 그날 GPS 재인증 | **구제권 자동 소모** |
| 만회 횟수 | 무제한 | **무료 월 1개 + 코인 구매** |
| 스트릭 | 연속 일수 (갭=끊김) | **누적 인증 횟수 (갭 무관)** |
| 리셋 위치 | 체크인 + 복귀만료 2곳 | **주간 채점 1곳** |

### 3.2 목표

- 주 **2~7회** (기본 3회)
- 변경은 **예약제** → 다음 달 1일에 반영
  주 중간에 목표를 낮춰 그 주를 통과하는 회피를 막는다
- 인증 방식(GPS/AI/GPS+AI) 변경은 **즉시 반영** — 채점 기준이 아니라 절차라서 회피에 못 쓴다

### 3.3 주간 채점 (매주 월 00:01 KST)

```
성공 횟수 >= 목표          →  ACHIEVED        스트릭 유지
미달 + 구제권 있음         →  RESCUED         구제권 1개 소모, 스트릭 유지, 코인 차감 없음
미달 + 구제권 없음         →  PENDING_RESCUE  ★ 아무것도 깎지 않고 유예
```

### 3.4 구제 유예 — 게임의 "이어하기"

미달을 즉시 실패시키면 사용자는 **새벽에 예고 없이 스트릭 0 + 코인 −500**을 맞는다.
오래 쌓은 사용자일수록 그 순간 이탈한다. 그래서 확정 전에 선택 기회를 준다.

```
PENDING_RESCUE  (스트릭·코인 그대로, 기한 2일)
   ├ 기한 내 사후 구매  →  RESCUED   1,200코인, 스트릭 유지
   └ 기한 경과          →  FAILED    스트릭 0 + 코인 −500   (매일 00:10 스케줄러)
```

### 3.5 구제권

| | 무료분 | 구매분 |
|---|---|---|
| 지급 | 가입 시 1개 + 매월 1일 1개 | 코인 구매 |
| 소멸 | **월말 소멸**(이월 없음) | 소멸 없음 |
| 소모 순서 | **먼저** 쓴다 (어차피 사라지므로 유리) | 나중 |

- 가격: **미리 사두기 800** / **사후 구매 1,200**
  미리 사두는 쪽이 이득이어야 "미리 사서 보관 후 사용" 원칙이 유지된다
- 구매 한도 없음
- 사용자가 "쓰는" 행위는 **없다** — 주간 채점이 자동 소모한다 (§6.2 상점 설계의 근거)
- 전부 설정값: `booster.weekly.*` 에서 한 줄로 조정

### 3.6 스트릭과 보상

- 스트릭 = **누적 인증 횟수**. 인증할 때마다 +1, 날짜 갭과 무관
- 초기화는 **주간 채점의 FAILED 확정 시에만**
- 마일스톤 보상: 7·14·21…회마다 **+100코인**, 인증 즉시 지급

---

## 4. 인증 방식 (A축·B축 공통)

지원하는 3종. 다른 값(`PHOTO`, `GPS_PHOTO`)은 **생성 단계에서 거절**한다 —
체크인이 처리할 수 없는 타입이라 그대로 두면 아무도 인증 못 하는 좀비 챌린지가 된다.

| 방식 | 흐름 |
|---|---|
| `GPS` | 체크인 즉시 확정 |
| `AI` | 체크인 → PENDING → 사진 업로드로 확정. **GPS 안 봄** |
| `GPS_PHOTO_AI` | GPS 통과해야 PENDING → 사진 업로드로 확정 |

### 4.1 ⚠️ AI 카테고리 제약

`ai-service` 는 **`EXERCISE` / `STUDY` 두 값만** 받는다(Pydantic Enum). 그런데:

- **백엔드는 이 값을 검증하지 않고** 클라이언트가 준 문자열을 그대로 전달한다
- **`challenges.category` 는 자유 문자열**이라 `"독서"` 같은 값으로 챌린지를 만들 수 있다
- **개인 트랙에는 카테고리를 저장하는 컬럼이 아예 없다**

그래서 `category:"독서"` + `verificationType:"AI"` 챌린지는 **생성·참여·체크인까지 전부 통과한 뒤
사진 업로드 단계에서 500**을 맞는다(백엔드가 upstream 4xx 를 "계약 오류"로 보고 500으로 바꾼다
— 사용자 입력 실수가 서버 장애로 집계된다). 인증 방식을 생성 단계에서 3종으로 제한해 막았던
"좀비 챌린지"와 **같은 모양의 결함이 카테고리 필드에 남아 있다.**

**현재 앱은 한글로 보낸다 → AI 챌린지가 전부 실패한다**

앱의 챌린지 카테고리는 `['운동', '공부', '독서', '기상']` 이고 이 **한글 문자열이 그대로**
서버를 거쳐 ai-service 로 간다. ai-service 는 `EXERCISE`/`STUDY` 만 아는 Enum이라
**넷 다 422 → 500**이다. 즉 지금 상태에서 AI 인증 챌린지는 하나도 작동하지 않는다.

**매핑 — 3개는 해결되고 1개가 남는다**

| 앱 카테고리 | AI 값 | 비고 |
|---|---|---|
| 운동 | `EXERCISE` | 그대로 대응 |
| 공부 | `STUDY` | 그대로 대응 |
| 독서 | **`STUDY`** | ai 프롬프트의 STUDY 통과 기준에 *"소설·에세이·자기계발서 등 활자책 독서 중"* 이 이미 있다 |
| **기상** | **없음** | 기상 인증 사진은 운동도 공부도 아니다 |

`EXERCISE`/`STUDY` 는 이름보다 넓다. 특히 `STUDY` 는 독서·인강·코딩까지 포함한다.

**확정 (2026-08-27) — 카테고리는 2개를 유지한다**

`ai-service` 를 늘리지 않고 앱이 맞춘다. MVP 범위를 넓히지 않기 위해서다.

- 앱은 AI 계열 인증에서 **`EXERCISE`/`STUDY` 영문 값**만 보낸다 (한글 금지).
  **표시용 한글과 전송값을 분리**한다 — 화면엔 "운동", 서버엔 `EXERCISE`
- **`독서` → `STUDY`** 로 매핑한다
- **`기상` 은 AI 인증 대상에서 제외**한다. 기상 챌린지에서는 인증 방식 선택지에 AI 계열을 빼고
  GPS 만 남긴다
- 개인 트랙은 앱이 카테고리를 지정해 보낸다 (서버에 저장소가 없다)

> **출처 메모**: 앱의 4종(kms224, 08-09)과 ai-service 의 2종(김태훈, 08-08)은 **각자 독립적으로
> 정해졌고 합의 기록이 없다.** 옛 `MVP_API_SPEC.md` 에는 `category` 가 언급조차 없었고,
> DB 는 `VARCHAR(50)` 자유 문자열이라 어긋남을 아무도 못 잡았다. 위 표가 최초의 합의본이다.
>
> 근본 해결(생성 단계에서 서버가 검증)은 후속 과제로 남긴다 (§12 백엔드).

### 4.2 GPS 실패 처리

**GPS 실패는 A축·B축 모두 400 즉시 거절**이며 거리를 함께 알려준다
(`"등록된 위치에서 2224m 떨어져 있습니다. (허용 50m)"`).
실패 레코드를 만들지 않으므로 그날 재시도가 가능하고, 참여율·정산에도 영향이 없다.

**AI 거절 시** 개인 체크인 레코드는 삭제한다 — PENDING이 하루를 점유해 재시도가 막히는 것을 방지.

**구조**: 팀은 재시도 이력이 필요해 제출 테이블을 두지만, 개인은 (user_id, date) 하루 1건이라 1:1로 붙인다.

```
팀    check_in → verification_submissions(N) → gps/ai_results → decisions
개인  check_in → personal_ai_verifications(1)
```

---

## 5. B축 — 팀 챌린지

### 5.1 구성

- 챌린지 = 카테고리 + 제목 + 인증 방식 + 기간(일) + 예치금 + 공개/비공개 + 자동/방장 승인
- **정원 10명 고정** — 팀 편성이 5:5 기준이라 다른 값이면 정원을 채워도 편성이 안 된다
- **방장은 생성과 동시에 CONFIRMED 참가자**가 되고 **예치금도 동일하게 차감**된다
  방장만 공짜면 정산 풀(예치금 × 인원)이 실제 징수액과 어긋난다
- 챌린지 생성 시 방장의 인증 기준 위치가 필요하다 (요청에 넣거나, 개인 인증 위치를 재사용)
- 10명이 차면 **서버가 랜덤 5:5 편성 + 자동 시작**(READY → ACTIVE)
- 시작 후 나가기 없음 (회원 탈퇴 예외)

### 5.2 참여율

```
참여율 = 팀 전체 인증 횟수 / (챌린지 기간 × 팀 인원)
```

- 탈퇴자: 탈퇴 전후로 분모를 분리해 재계산. 예치금 반환 없음
- 정산은 저장된 값이 아니라 **체크인 테이블 재계산값**을 쓴다(자가 치유)

### 5.3 정산

| 결과 | 처리 |
|---|---|
| 승팀 | 전체 모금 코인 / 승팀 인원 |
| 패팀 | 예치금 소멸 |
| 동률 | 전원 예치금 반환 |

---

## 6. 상점 ★ 신규

### 6.1 배경

프론트(`BS-38`)가 '준비 중' 플레이스홀더를 실제 상점으로 채웠다. 그 시점 기준으로
"서버에 상점이 없다"고 판단해 **카탈로그·보유 수량·구매를 전부 앱 로컬에 구현**했는데,
그 판단은 **이 브랜치 기준으로는 틀렸다.** 구제권 구매는 이미 백엔드에 있다.

### 6.2 설계 결정 — 상점 테이블을 만들지 않는다

파는 물건이 **구제권 하나**이고, 그건 이미 도메인 API(`POST /api/personal/recovery-tickets`)를
갖고 있다. 물건 하나를 위해 범용 상품·주문 테이블을 만드는 건 과설계다.

**상점은 화면 개념이고, 서버에서는 기존 구제권 API로 매핑한다.**

| 상점 동작 | 매핑 | 비고 |
|---|---|---|
| 카탈로그 | **앱이 보유** | 구제권 가격만 서버 값(`ticketPrice`)으로 덮어쓴다 |
| 구제권 구매 | `POST /api/personal/recovery-tickets` | 800코인. 잔액 부족 시 400 |
| 보유 수량 | `GET /api/personal/weekly-goal` → `freeTickets` / `paidTickets` | **서버가 단일 진실 원천** |
| 구제권 "사용" | **없음** | 주간 채점이 자동 소모 (§3.5) |
| 구제 대기 중 즉시 구제 | `POST /api/personal/rescue` | 1,200코인. "사용"에 가장 가까운 동작 |
| 기프티콘 | **판매 안 함** | `purchasable=false`, 화면만 존재 |

### 6.3 지켜야 할 규칙

**① 코인을 직접 움직이는 API는 만들지 않는다.**
프론트가 규약해둔 `POST /api/users/me/coins {amount:-100}` 는 **구현하지 않는다.**
클라이언트가 잔액을 임의로 조작할 수 있게 되어 코인 경제가 무너진다.
코인은 서버 이벤트(가입·마일스톤·구매·정산)로만 움직이고, 모든 변동은
`coin_transactions` 에 사유와 함께 남는다. `GET /api/users/me/coins` 는 조회 전용이다.

**② 보유 수량을 기기에 저장하지 않는다.**
`SharedPreferences` 인벤토리는 제거한다. 구제권은 `users.free_recovery_tickets` /
`paid_recovery_tickets` 에 있고 주간 채점 스케줄러가 서버에서 소모한다.
기기에 따로 두면 기기 교체·재설치 시 사라지고 서버 값과 갈라진다.

**③ 기프티콘은 재고·발급이 생기기 전까지 팔지 않는다.**
코인만 받고 물건이 안 나가는 상태가 된다. Phase 2.

### 6.4 프론트 정렬 필요 (BS-38 → 이 문서 기준)

| 항목 | 현재 앱 | 맞춰야 할 값 |
|---|---|---|
| 구제권 가격 | 100 | **800** (`ticketPrice` 로 받을 것) |
| 구제권 의미 | 복귀 미션 코인 환급(−50/−100 되돌리기) | **주간 목표 미달 시 자동 소모** |
| 구매 경로 | `POST /users/me/coins` + 로컬 인벤토리 | **`POST /api/personal/recovery-tickets`** |
| 보유 수량 | SharedPreferences | **`GET /api/personal/weekly-goal`** |
| "사용" 버튼 | 코인 환급 | **제거**. 대신 `pendingRescueWeek` 있을 때 "지금 구제하기" |

---

## 7. 코인 규칙

`CoinTransactionReason` 기준. 모든 변동은 `coin_transactions` 에 사유·잔액과 함께 기록된다.

| 사유 | 코인 | 비고 |
|---|---|---|
| `SIGNUP_BONUS` | **+500** | 가입 시 |
| `STREAK_REWARD` | **+100** | 7·14·21…회 마일스톤, 인증 즉시 |
| `WEEKLY_MISS_PENALTY` | **−500** | 주간 미달 확정(FAILED) |
| `RECOVERY_TICKET_PURCHASE` | **−800** | 구제권 미리 사두기 |
| `LATE_RESCUE_PURCHASE` | **−1,200** | 구제 유예 중 사후 구매 |
| `CHALLENGE_DEPOSIT` | −예치금 | 챌린지 참가(방장 포함) |
| `SETTLEMENT_WIN` | +모금/승팀 인원 | 정산 승리 |
| `DEPOSIT_REFUND` | +예치금 | 동률 정산 |
| `DEPOSIT_CANCEL_REFUND` | +예치금 | 참가 취소 |
| ~~`RECOVERY_SUCCESS`~~ / ~~`RECOVERY_FAILURE`~~ | — | **폐지.** 과거 데이터 보존용으로 enum 에만 남음 |

금액은 전부 설정값(`booster.weekly.*`, `booster.streak.*`, `booster.coin.*`).

---

## 8. 도메인 모델 (실제 19개 테이블)

**공통**

| 테이블 | 설명 |
|---|---|
| `users` | 계정, 코인 잔액, 누적 출석, **구제권(무료/구매)**, 지급 멱등키 |
| `coin_transactions` | 코인 변동 내역 (사유·금액·잔액) |
| `streaks` | 누적 인증 횟수 + 최고 기록 |
| `shedlock` | 다중 인스턴스 스케줄러 분산락 |

**A축 — 개인 습관**

| 테이블 | 설명 |
|---|---|
| `personal_locations` | 인증 기준 좌표·반경 + **주간 목표 + 인증 방식** (user_id PK) |
| `personal_check_ins` | 개인 인증 기록. `UNIQUE(user_id, check_in_date)` |
| `personal_ai_verifications` | 개인 AI 판정 (체크인과 1:1) |
| `weekly_evaluations` | 주간 채점 결과. `UNIQUE(user_id, week_start)` 로 멱등 보장 |

**B축 — 팀 챌린지**

| 테이블 | 설명 |
|---|---|
| `challenges` | 챌린지 설정 |
| `challenge_participants` | 참여자 + 개별 GPS 위치 + 팀 배정 |
| `teams` | 챌린지 내 경쟁 단위 (A/B), 참여율 |
| `challenge_check_ins` | 팀 인증 기록 |
| `verification_submissions` | 인증 제출 단위 (체크인 1:N) |
| `gps_verification_results` / `ai_verification_results` | 제출별 판정 결과 |
| `verification_decisions` | 최종 판정 |
| `settlements` | 정산 결과 |
| `chat_messages` / `cheer_emojis` | 팀 채팅 · 응원 |

**존재하지 않는 테이블** (이전 문서에 있었으나 미구현 또는 폐지):
`recovery_missions`(폐지) · `team_members`(팀은 챌린지 종속이라 불필요) ·
`leaderboards`(체크인에서 계산) · `notifications` · `user_settings` · `challenge_rules` ·
~~`verification_logs`~~(미채택)

---

## 9. 변경 이력 — 이전 판과 달라진 점

다른 파트가 옛 문서를 보고 구현했다면 아래가 어긋난다.

| # | 이전 | 현재 |
|---|---|---|
| 1 | 복귀 미션 (매일, −50/−100) | **폐지** → 주간 목표 + 구제권 (§3) |
| 2 | 스트릭 = 연속 일수 | **누적 인증 횟수** |
| 3 | 개인 인증은 GPS 고정 | **GPS / AI / GPS+AI 선택** (§4) |
| 4 | AI 인증은 Phase 2 | **구현 완료** (개인·팀 양쪽) |
| 5 | 정원 2~10 가변 | **10명 고정** |
| 6 | 방장은 참가자가 아님 | **자동 참가 + 예치금 차감** |
| 7 | 팀 GPS 실패는 서버 로그만 | **400 + 거리 안내** (개인과 통일) |
| 8 | 팀 생성 API (`POST /api/teams`) | **없음.** 정원 충족 시 서버가 자동 편성 |
| 9 | 챌린지가 팀에 종속 (`/api/teams/{id}/challenges`) | **`/api/challenges`** 로 독립 |
| 10 | 상점 없음 | **구제권 판매** (§6) |
| 11 | `notifications` / `user_settings` / `challenge_rules` | **미구현.** Phase 2 |

---

---

## 10. 화면 명세 (앱 UI ↔ API)

> 실제 Flutter 코드(`feature/BS-38-flutter-app`)를 기준으로 작성했다.
> **서버 기준으로 무엇이 맞는지**를 적었으므로 앱을 이쪽에 맞춘다.
> 섹션 번호는 `S-` 접두어를 쓴다.

## S-1. 앱 전체 구조

### S-1.1 진입

```
앱 시작 → LoginScreen
            ├ 로그인 성공 → MainScaffold
            └ 회원가입 → SignupScreen → (가입 응답의 토큰으로 즉시 로그인) → MainScaffold
```

**세션 만료(401)** 시 어디서든 `LoginScreen(sessionExpired: true)` 로 전체 스택을 교체한다
(`appNavigatorKey` + `ApiClient.onUnauthorized`). 회원 탈퇴한 계정도 서버가 401을 주므로 같은 경로다.

### S-1.2 하단 5탭 (`MainScaffold`)

| # | 탭 | 아이콘 | 루트 화면 | 축 |
|---|---|---|---|---|
| 0 | **홈** | `home_rounded` | `HomeScreen` | A |
| 1 | **팀** | `groups_rounded` | `TeamHomeScreen` | B |
| 2 | **인증** | `verified_rounded` (가운데 FAB 강조) | `VerifyScreen` | A+B |
| 3 | **상점** | `storefront_rounded` | `ShopScreen` | A |
| 4 | **마이페이지** | `person_rounded` | `MyPageScreen` | 공통 |

- 탭마다 **독립 Navigator**(`IndexedStack` + 탭별 `GlobalKey`) → 탭을 옮겨도 각 탭의 depth가 유지된다
- **같은 탭 재탭** → 그 탭의 루트로 pop
- **뒤로가기**: 현재 탭에서 pop → 더 없으면 홈 탭으로 → 홈에서는 앱을 닫지 않음(`canPop: false`)

### S-1.3 화면 전이도

```
LoginScreen ──▶ SignupScreen
     │
     ▼
MainScaffold
 ├ [홈]   HomeScreen ──▶ PersonalCreateScreen ──▶ LocationPickerScreen
 ├ [팀]   TeamHomeScreen ┬─▶ TeamExploreScreen ──▶ TeamDetailScreen ──▶ TeamWaitingScreen
 │                       └─▶ TeamCreateScreen ─┬─▶ OwnerCodeScreen
 │                                             └─▶ TeamWaitingScreen ──▶ TeamBattleScreen
 ├ [인증] VerifyScreen ──▶ PersonalCreateScreen  (+ GPS 인증 바텀시트)
 ├ [상점] ShopScreen  (구매/사용 확인 바텀시트)
 └ [마이] MyPageScreen ─┬─▶ CoinHistoryScreen
                        └─▶ LoginScreen (로그아웃·탈퇴)
```

---

## S-2. 인증 화면

### S-2.1 LoginScreen

| | |
|---|---|
| **입력** | 이메일, 비밀번호 |
| **API** | `POST /api/auth/login` |
| **성공** | `accessToken`·`userId`·`nickname` 을 `Session` 에 저장 → `MainScaffold` 로 스택 교체 |
| **실패** | 401 `INVALID_CREDENTIALS` — 이메일 존재 여부를 구분해 알려주지 않는다(계정 열거 방지) |
| **변형** | `sessionExpired: true` 로 진입 시 "세션이 만료되었습니다" 안내 |

### S-2.2 SignupScreen

| | |
|---|---|
| **입력** | 이메일, 비밀번호, 닉네임 |
| **API** | `POST /api/auth/signup` |
| **성공** | **응답에 `accessToken` 이 들어 있다.** 그대로 세션에 넣고 진입 — `login` 을 다시 부르지 말 것 (BCrypt가 두 번 돌아 체감 지연 2배) |
| **부수 효과** | 서버가 **가입 보너스 500코인 + 무료 구제권 1개**를 지급 |
| **실패** | 409 `DUPLICATE_EMAIL` |

---

## S-3. 홈 탭 — `HomeScreen`

개인 습관(A축)의 현황판. **인증 위치 등록 여부로 화면이 완전히 갈린다.**

### S-3.1 로딩 시 호출

```
GET /api/dashboard/home       대시보드
GET /api/users/me/location    위치 (없으면 빈 화면 분기)
GET /api/users/me             코인·닉네임
```

> 앱은 여기서 `RecoveryService.fetchStatus()` 도 부른다 → **삭제된 API. 404.** §S-3.4 참조

### S-3.2 위치 미등록 — `_emptyBody()`

- "시작 전 알아두기" 안내 카드
- **[인증 장소 등록하기]** → `PersonalCreateScreen`

이 상태에서는 `GET /api/personal/weekly-goal` 과 `POST /api/personal/check-in` 이
**400 `LOCATION_NOT_REGISTERED`** 를 준다. 위치 등록이 A축의 전제조건이다.

### S-3.3 위치 등록 후 — `_activeBody()`

| 섹션 | 내용 | 출처 |
|---|---|---|
| **히어로** | 보유 코인 | `dashboard.coinBalance` |
| **주간 링** | 이번 주 달성률 % | `weeklySuccessCount` / 목표 |
| **스탯 카드 1** | 현재 스트릭 / 최고 스트릭 | `dashboard.streak.current` / `.max` |
| **스탯 카드 2** | 다음 보상 `+100`, "7일 연속 인증 · N일 남음" | 스트릭에서 계산 |
| **인증 기준 장소** | 장소명 + [변경] | `GET /api/users/me/location` |
| **캘린더** | 월별 인증 기록 | `dashboard.calendar.days[].status` |

### S-3.4 정렬 필요

| 항목 | 현재 앱 | 서버 기준 |
|---|---|---|
| `RecoveryService.fetchStatus()` 호출 | `GET /api/personal/recovery/status` → **404** | **삭제.** 호출부 제거 |
| "복귀 미션" 히어로 분기 (`_isRecovery`) | 복귀 상태에 따라 UI 변경 | **폐지.** 제거 |
| 주간 목표가 안 보임 | 링에 목표 대비 %만 | **`GET /api/personal/weekly-goal` 추가** — `targetDays`, `successCount`, `remainingDays` |
| **구제 안내 팝업 없음** | — | **`pendingRescueWeek` 이 null이 아니면 팝업 필수** (§S-7.4) |
| 스트릭 라벨 "7일 연속" | 연속 일수로 표기 | **누적 인증 횟수**다. "7회마다" 로 문구 수정 |

---

## S-4. 팀 탭 (B축)

### S-4.1 `TeamHomeScreen` — 참여 중 챌린지 허브

| 상태 | 표시 |
|---|---|
| 참여 챌린지 없음 | [탐색하기] → `TeamExploreScreen` / [만들기] → `TeamCreateScreen` |
| 참여 중 · `READY` | `TeamWaitingScreen` (모집 대기) |
| 참여 중 · `ACTIVE` | `TeamBattleScreen` (대결) |

**API**: `GET /api/challenges/{id}` (`ChallengeService.fetchDetail`)

> ⚠️ **정렬 필요**: 참여 중인 챌린지를 어떻게 아는지가 문제다.
> 서버에 **`GET /api/users/me/challenges`** 가 있으므로 그걸 써야 한다.
> 앱이 로컬에 챌린지 id를 들고 있으면 재설치 시 잃어버리고, 서버에서 취소·종료된 챌린지를
> 알 수 없어 잘못된 상태를 보여준다.

### S-4.2 `TeamExploreScreen` — 탐색

| | |
|---|---|
| **API** | `GET /api/challenges?category=&keyword=&page=&size=` |
| **초대 코드** | `GET /api/challenges/invite/{code}` |
| **표시** | 제목·카테고리·기간·예치금·정원(항상 10)·`joined` 배지 |
| **전이** | 항목 탭 → `TeamDetailScreen` |

각 항목의 `joined` 로 이미 참여한 챌린지를 구분한다 — 없으면 눌렀을 때 409를 맞는다.

### S-4.3 `TeamCreateScreen` — 생성

| | |
|---|---|
| **입력** | 카테고리, 제목, 설명, 인증 방식, 기간(일), 예치금, 공개/비공개, 승인 방식 |
| **API** | `POST /api/challenges` |
| **전이** | 비공개면 `OwnerCodeScreen`(초대 코드) → `TeamWaitingScreen` |

**서버 규칙 (필수 반영)**

| 필드 | 규칙 |
|---|---|
| `maxParticipants` | **10 고정.** 입력 UI를 두지 말 것 (다른 값은 400) |
| `verificationType` | **`GPS` / `AI` / `GPS_PHOTO_AI` 만.** `PHOTO`·`GPS_PHOTO` 는 400 |
| `category` | 자유 문자열이라 서버는 통과시키지만, **AI 계열을 고르면 사진 업로드에서 500**이 난다. 아래 참조 |
| `gpsLat`/`gpsLng`/`gpsRadiusMeters` | **필수.** 방장이 곧바로 참가자가 되므로. 생략 시 개인 인증 위치를 재사용하고, 둘 다 없으면 400 `LOCATION_REQUIRED` |

> ⚠️ **카테고리를 한글로 보내면 AI 인증이 전부 실패한다.**
> 현재 앱은 `['운동','공부','독서','기상']` 한글 문자열을 그대로 보내는데, `ai-service` 는
> `EXERCISE`/`STUDY` 만 아는 Enum이라 **넷 다 500**이 난다(생성·참여·체크인까지는 통과하고
> 사진 업로드에서 터진다).
>
> | 앱 카테고리 | AI 로 보낼 값 |
> |---|---|
> | 운동 | `EXERCISE` |
> | 공부 | `STUDY` |
> | 독서 | `STUDY` (프롬프트에 활자책 독서 통과 기준이 있다) |
> | **기상** | **없음 — AI 인증 대상 제외(확정).** 인증 방식 선택지에서 AI 계열을 빼고 GPS 만 남길 것 |
>
> 표시용 한글과 **서버로 보내는 값을 분리**해야 한다.

**방장은 생성과 동시에 CONFIRMED 참가자가 되고 예치금이 차감된다.**
따라서 생성 화면에 "예치금 N코인이 지금 차감됩니다" 안내가 필요하고,
생성 직후 "참가하기" 버튼을 노출하면 안 된다(409).

> ⚠️ 생성 응답의 `joined` 가 `false` 로 온다(방장은 이미 참가자인데). 서버 쪽 표기 문제이므로
> 앱은 **생성 성공 = 참가 완료**로 취급한다.

### S-4.4 `TeamDetailScreen` — 상세 · 참가

| | |
|---|---|
| **API** | `GET /api/challenges/{id}` · `POST /api/challenges/{id}/participants` |
| **입력** | 각오 한마디(`personalStatement`) + **본인 GPS 인증 위치** (`LocationService.current()`) |
| **전이** | 참가 성공 → `TeamWaitingScreen` |

**에러 처리**

| 코드 | 메시지 |
|---|---|
| 409 `ALREADY_APPLIED` | 이미 참여 중 |
| 409 정원 초과 | 자리가 찼어요 |
| 409 `CHALLENGE_ALREADY_STARTED` | 이미 시작된 챌린지 |
| **409 `DATA_CONFLICT`** | ⚠️ 반경이 0 이하일 때. 서버 검증 누락으로 400이 아닌 409가 온다 |

### S-4.5 `TeamWaitingScreen` — 모집 대기

| | |
|---|---|
| **API** | `GET /api/challenges/{id}` (폴링) · `DELETE /api/challenges/{id}/participants/{userId}` (취소) |
| **표시** | 현재 인원 / 10, 초대 코드(비공개) |
| **전이** | `status` 가 `ACTIVE` 로 바뀌면 → `TeamBattleScreen` |

**10명이 차면 서버가 자동으로 5:5 편성 + `READY → ACTIVE` 전환**한다.
앱이 시작을 트리거하지 않는다 — 상태 변화를 **감지**할 뿐이다.

> ⚠️ **미구현**: 방장 승인(`LEADER`) 방식 챌린지의 승인 화면이 없다.
> `GET /api/challenges/{id}/participants?status=PENDING` 으로 대기자를 받고
> `POST /api/challenges/{id}/participants/{participantId}/approve` 로 승인해야 한다.
> `participantId` 는 목록 응답의 `data[].id` 이며, **이 목록이 유일한 획득 경로다.**

### S-4.6 `TeamBattleScreen` — 대결 · 결과

| | |
|---|---|
| **API** | `GET /api/challenges/{id}/team-detail` · `GET /api/challenges/{id}/result` |
| **표시** | 우리 팀 vs 상대 팀 참여율, 팀원별 인증 현황 |
| **종료 후** | 정산 결과(WIN/LOSE/DRAW, 지급 코인) |

**미연결 API** (화면은 있으나 안 붙었거나, 붙일 자리가 있음):
`GET /api/challenges/{id}/leaderboards` · `POST /api/challenges/{id}/cheers` ·
`GET`·`POST`·`DELETE /api/teams/{teamId}/chat`

---

## S-5. 인증 탭 — `VerifyScreen`

**A축과 B축 인증이 한 화면에 같이 있다.**

### S-5.1 로딩 시 호출

```
GET /api/personal/check-in/today     오늘 개인 인증 상태
GET /api/users/me/location           위치
GET /api/challenges/{id}             참여 중 팀 챌린지 (있으면)
GET /api/challenges/{id}/check-ins   팀 인증 현황
```

> 앱은 `RecoveryService.fetchStatus()` 도 부른다 → **404. 제거 대상**

### S-5.2 화면 구성

| 섹션 | 조건 | 내용 |
|---|---|---|
| **오늘의 인증** | 항상 | 개인 습관 카드 |
| ~~복귀 미션~~ | `hasPendingMission` | **폐지. 제거** |
| **팀 챌린지** | 참여 중일 때 | 팀 인증 카드 |
| **인증 장소가 없어요** | 위치 미등록 | → `PersonalCreateScreen` |

### S-5.3 GPS 인증 바텀시트 (`_VerifyStage`)

```
locating   ─ 기기 GPS 좌표 수신 중 (레이더 애니메이션)
  ↓
submitting ─ 서버에 제출 중 ("인증 처리 중…")
  ↓
passed     ─ 성공. 스트릭·코인 갱신 표시
failed     ─ 서버 판정 실패 (반경 밖 등)
error      ─ 좌표를 못 받았거나 요청 자체가 실패
```

**호출**

| 축 | API | 본문 |
|---|---|---|
| A축 | `POST /api/personal/check-in` | `{"lat":…, "lng":…}` |
| B축 | `POST /api/challenges/{id}/check-ins` | `{"currentLat":…, "currentLng":…}` |

> ⚠️ **필드명이 축마다 다르다.** A축은 `lat`/`lng`, B축은 `currentLat`/`currentLng`.

**GPS 실패 = 400 `GPS_OUT_OF_RANGE`** (A·B 공통). 응답 `message` 에 거리가 들어 있으므로
(`"등록된 위치에서 2224m 떨어져 있습니다. (허용 50m)"`) **그대로 노출하면 된다.**
실패해도 서버에 레코드가 남지 않아 **그날 다시 시도할 수 있다.**

### S-5.4 ⚠️ 미구현 — AI 사진 인증

**현재 앱에는 사진 업로드 UI가 없다. 그래서 개인·팀 모두 AI 인증을 실제로 못 쓴다.**
서버는 준비돼 있다.

```
1) 체크인          POST /api/personal/check-in        → status="PENDING", checkInId
   (팀)            POST /api/challenges/{id}/check-ins → status="PENDING", submissionId

2) 사진 업로드     POST /api/personal/check-in/{checkInId}/ai-verification
   (팀)            POST /api/verification-submissions/{submissionId}/ai-verification
                   multipart/form-data — image(파일), category(문자열)

3) 결과            passed=true  → 확정, 스트릭 +1
                   passed=false → 개인은 체크인이 삭제됨 → 그날 재시도 가능
```

**제약**: 10MB 초과 413 · `image/jpeg`·`png`·`webp` 외 415 · AI 서비스 미기동 시 502
(502여도 체크인은 PENDING으로 남아 재시도 가능)

**필요한 UI**

- 체크인 응답 `status == "PENDING"` 이면 → 사진 촬영/선택 화면으로 유도
- `GET /api/personal/check-in/today` 가 `PENDING` 이면 → "사진 인증이 남았어요" 배너
- 업로드 후 `passed`·`reason`·`confidenceScore` 표시

---

## S-6. 상점 탭 — `ShopScreen` ★

### S-6.1 현재 앱 구현 (BS-38)

| 영역 | 내용 |
|---|---|
| **내 보유함** | 구제권 보유 수 · [사용] 버튼 |
| **구제권** 섹션 | 가격 100 · [구매] / [코인 부족] |
| **기프티콘** 섹션 | 아메리카노 4,500 / 편의점 5,000 / 영화 12,000 / 치킨 … — **`준비 중` 잠금** |
| 구매·사용 | 확인 바텀시트(구매 후 잔액 미리보기) → 토스트 |

**앱이 세운 전제와 실제**

| 앱의 전제 | 실제 (`integration/a-b-axis`) |
|---|---|
| "서버에 상점이 없다" | 구제권 구매 API가 **있다** |
| 보유 수량을 기기(`SharedPreferences`)에 저장 | `users.free_recovery_tickets` / `paid_recovery_tickets` |
| `POST /api/users/me/coins` 로 잔액 증감 | **없고, 만들지 않는다** |
| 구제권 = 복귀 미션 코인 환급(−50/−100 되돌리기) | **복귀 미션은 폐지.** 주간 목표 미달 시 자동 소모 |
| 가격 100 | **800**(미리 사두기) / **1,200**(사후 구매) |

### S-6.2 서버 기준 설계

상점 전용 API는 만들지 않는다. 파는 물건이 구제권 하나이고 이미 도메인 API가 있다
(근거: `docs/project-plan.md` §S-6).

| 상점 동작 | 호출 |
|---|---|
| 카탈로그 | 앱이 보유. **가격만** `ticketPrice` 로 덮어쓴다 |
| 구제권 구매 | `POST /api/personal/recovery-tickets` → `{recoveryTickets, price, coinBalance}` |
| 보유 수량 | `GET /api/personal/weekly-goal` → `freeTickets` / `paidTickets` |
| 구제권 "사용" | **없음** |
| 구제 대기 중 즉시 구제 | `POST /api/personal/rescue` |
| 기프티콘 | 판매 안 함 (`purchasable=false` 유지) |

### S-6.3 왜 "사용" 버튼이 없어야 하나

구제권은 **사용자가 쓰는 물건이 아니다.** 매주 월 00:01 채점에서 목표 미달이면
서버가 자동으로 1개를 소모한다(무료분 → 구매분 순). 사용자가 할 일은 **미리 사두는 것**뿐이다.

"사용"에 가장 가까운 동작은 **구제 대기 중 사후 구매**(`POST /api/personal/rescue`)이고,
이건 상점이 아니라 **구제 안내 팝업**(§S-7.4)에서 일어난다.

### S-6.4 화면 재구성안

```
[내 구제권]
  무료 1개  (이번 달 말 소멸)      ← freeTickets
  구매 2개  (소멸 없음)            ← paidTickets
  ─────────────────────────────
  목표를 못 채운 주에 자동으로 1개 사용돼요.
  스트릭이 지켜지고 코인도 안 깎여요.

[구제권 구매]
  800코인  [구매]                  ← ticketPrice, POST /api/personal/recovery-tickets
  미리 사두면 800, 놓친 뒤에 사면 1,200이에요.

[기프티콘]   준비 중
```

### S-6.5 정렬 체크리스트

- [ ] `core/inventory.dart` (SharedPreferences) **삭제** — 서버가 단일 진실 원천
- [ ] `ShopService.purchase` → `POST /api/personal/recovery-tickets`
- [ ] `ShopService.use` **삭제**
- [ ] `ShopService._moveCoins` / `_isMissingEndpoint` **삭제** (`POST /users/me/coins` 는 안 생긴다)
- [ ] `ShopCatalog.recoveryTicket.price` 하드코딩 100 → 서버 `ticketPrice`
- [ ] `refundAmount` 개념 **삭제**
- [ ] 보유 수량을 무료/구매로 나눠 표시 (소멸 규칙이 다르다)
- [ ] 잔액 부족 판정을 앱이 하지 말고 **서버 400**을 받아 처리 (앱 판정은 유지해도 되지만 서버가 최종)

---

## S-7. 마이페이지 탭 — `MyPageScreen`

| | |
|---|---|
| **API** | `GET /api/users/me` |
| **표시** | 닉네임, 이메일, 가입일, 누적 출석(`totalAttendance`), 보유 코인 |
| **전이** | [코인 내역] → `CoinHistoryScreen` |
| **로그아웃** | `POST /api/auth/logout` + `Session.clear()` → `LoginScreen` |
| **회원 탈퇴** | `DELETE /api/users/me` (204) → `LoginScreen` |

**탈퇴는 soft delete**다. 서버가 매 요청 `is_active` 를 확인하므로 남아 있는 토큰도 즉시 401이 된다.

### S-7.1 `CoinHistoryScreen`

| | |
|---|---|
| **API** | `GET /api/users/me/coins?page=&size=` (size 상한 100) |
| **표시** | 사유·금액·잔액·시각 |

**사유 한글 매핑** (`type` → 문구)

| type | 문구 |
|---|---|
| `SIGNUP_BONUS` | 가입 축하 |
| `STREAK_REWARD` | 연속 인증 보상 |
| `WEEKLY_MISS_PENALTY` | 주간 목표 미달 |
| `RECOVERY_TICKET_PURCHASE` | 구제권 구매 |
| `LATE_RESCUE_PURCHASE` | 구제권 사후 구매 |
| `CHALLENGE_DEPOSIT` | 챌린지 예치금 |
| `SETTLEMENT_WIN` | 챌린지 승리 |
| `DEPOSIT_REFUND` | 예치금 반환 |
| `DEPOSIT_CANCEL_REFUND` | 참가 취소 환불 |
| ~~`RECOVERY_SUCCESS`~~ / ~~`RECOVERY_FAILURE`~~ | 과거 데이터에만 존재. "복귀 미션"으로 표시하되 신규 발생 없음 |

---

## S-8. ⚠️ 미구현 화면 — 주간 목표

**서버에 있으나 앱에 대응 화면이 없다.** A축의 핵심인데 사용자가 볼 방법이 없다.

### S-8.1 주간 목표 설정

| | |
|---|---|
| **조회** | `GET /api/personal/weekly-goal` |
| **변경** | `PUT /api/personal/weekly-goal` `{"targetDays":5, "verificationType":"AI"}` |

**표시할 것**

```
이번 주 (8/24~8/30)
  ●●○  2 / 3 회      ← successCount / targetDays
  4일 남음            ← remainingDays

주간 목표      주 3회  [변경]
  변경은 다음 달 1일부터 적용돼요     ← pendingTargetDays 있으면 "다음 달부터 주 5회"

인증 방식      GPS  [변경]           ← verificationType, 즉시 반영
```

**주의**

- `targetDays` 는 2~7. 변경은 **예약제 → 다음 달 1일 반영**. 즉시 바뀌지 않으니 안내 필수
- `verificationType` 은 **즉시 반영**. 목표와 반영 시점이 다르다
- `GPS` / `AI` / `GPS_PHOTO_AI` 만 선택지로 노출 (나머지는 400)

### S-8.2 스트릭 표기

**스트릭은 연속 일수가 아니라 누적 인증 횟수다.** 하루 걸러 인증해도 끊기지 않는다.
초기화는 **주간 목표 미달이 FAILED로 확정될 때만** 일어난다.
"7일 연속" 같은 문구는 전부 "7회마다"로 바꿔야 한다.

### S-8.3 구제권 안내

무료분은 **이번 달 말에 소멸**하고 구매분은 남는다. 홈이나 상점에서 이 차이를 안내한다.

### S-8.4 ★ 구제 안내 팝업 (필수)

**없으면 사용자가 예고 없이 스트릭 0 + 코인 −500을 맞는다.** 이걸 막으려고 서버가
유예 기간을 두는 것이므로, 팝업이 없으면 유예 기능 자체가 무의미해진다.

```
조건: GET /api/personal/weekly-goal 의 pendingRescueWeek != null

┌─────────────────────────────────────┐
│  지난주 목표를 못 채웠어요            │
│                                     │
│  8/17~8/23   2 / 3 회               │
│  {rescueDeadline} 까지 구제할 수 있어요 │
│                                     │
│  지금 구제하면                        │
│    스트릭 유지 · 코인 차감 없음        │
│  그냥 두면                           │
│    스트릭 0 · 코인 500 차감          │
│                                     │
│  [1,200코인으로 구제하기]  [나중에]   │
└─────────────────────────────────────┘
        │
        └─▶ POST /api/personal/rescue
              200 → 스트릭·코인 유지 확정
              404 NO_PENDING_RESCUE   이미 처리됨
              400 RESCUE_DEADLINE_PASSED  기한 지남
              400 잔액 부족
```

**언제 띄우나**: 앱 포그라운드 진입 시 · 홈 탭 진입 시.
기한이 2일뿐이라 놓치면 되돌릴 수 없다.

---

## S-9. 화면 ↔ API 전체 매핑

| API | 사용 화면 | 상태 |
|---|---|---|
| `POST /api/auth/signup` | SignupScreen | ✅ |
| `POST /api/auth/login` | LoginScreen | ✅ |
| `POST /api/auth/logout` | MyPageScreen | ✅ |
| `GET /api/users/me` | MyPage · Home · Shop | ✅ |
| `DELETE /api/users/me` | MyPageScreen | ✅ |
| `GET /api/users/me/coins` | CoinHistoryScreen | ✅ |
| `GET /api/dashboard/home` | HomeScreen | ✅ |
| `POST`·`GET`·`PUT /api/users/me/location` | PersonalCreateScreen · Home · Verify | ✅ |
| `POST /api/personal/check-in` | VerifyScreen | ✅ |
| `GET /api/personal/check-in/today` | VerifyScreen | ✅ |
| `POST /api/personal/check-in/{id}/ai-verification` | — | ❌ **미구현** |
| `GET /api/personal/weekly-goal` | — | ❌ **미구현** |
| `PUT /api/personal/weekly-goal` | — | ❌ **미구현** |
| `POST /api/personal/recovery-tickets` | ShopScreen | ⚠️ **로컬 폴백 중** |
| `POST /api/personal/rescue` | — | ❌ **미구현** |
| `POST`·`GET /api/challenges` | TeamCreate · TeamExplore | ✅ |
| `GET /api/challenges/{id}` | TeamHome · Detail · Waiting | ✅ |
| `GET /api/challenges/invite/{code}` | TeamExploreScreen | ✅ |
| `GET /api/users/me/challenges` | — | ❌ **미사용** (로컬 보관 중) |
| `POST /api/challenges/{id}/participants` | TeamDetailScreen | ✅ |
| `GET /api/challenges/{id}/participants` | — | ❌ **미구현** (방장 승인 불가) |
| `POST /api/challenges/{id}/participants/{participantId}/approve` | — | ❌ **미구현** |
| `DELETE /api/challenges/{id}/participants/{userId}` | TeamWaitingScreen | ✅ |
| `GET /api/challenges/{id}/teams` | — | ❌ 미사용 |
| `POST`·`GET /api/challenges/{id}/check-ins` | VerifyScreen | ✅ |
| `GET /api/challenges/{id}/team-detail` | TeamBattleScreen | ✅ |
| `POST /api/verification-submissions/{submissionId}/ai-verification` | — | ❌ **미구현** |
| `GET /api/challenges/{id}/result` | TeamBattleScreen | ✅ |
| `GET /api/challenges/{id}/leaderboards` | — | ❌ 미사용 |
| `POST /api/challenges/{id}/cheers` | — | ❌ 미사용 |
| `GET`·`POST /api/teams/{teamId}/chat` · `DELETE /api/teams/{teamId}/chat/{messageId}` | — | ❌ 미사용 |
| ~~`GET /api/personal/recovery/status`~~ | Home · Verify | 🔴 **삭제된 API를 호출 중 (404)** |
| ~~`POST /api/personal/recovery`~~ | VerifyScreen | 🔴 **삭제된 API를 호출 중 (404)** |
| ~~`POST /api/users/me/coins`~~ | ShopScreen | 🔴 **존재하지 않고 만들지 않음** |

---

## S-10. 우선순위

### P0 — 지금 깨져 있다

1. `recovery_service.dart` · `models/recovery.dart` **삭제**, Home·Verify의 호출부 제거 (404 발생 중)
2. **상점을 서버 API로 전환** (§S-6.5) — 가격 800, 로컬 인벤토리 제거, "사용" 삭제
3. **구제 안내 팝업** (§S-8.4) — 없으면 유예 기능이 무의미

### P1 — 기능이 안 보인다

4. **주간 목표 화면** (§S-8.1) — A축 핵심인데 볼 방법이 없다
5. **AI 사진 업로드** (§S-5.4) — 없으면 AI 인증을 못 쓴다
6. `GET /api/users/me/challenges` 로 참여 챌린지 복원 (§S-4.1)
7. **방장 승인 화면** (§S-4.5) — `LEADER` 승인 챌린지가 작동 불가

### P2 — 정합성

8. 스트릭 문구를 "연속 일수" → "누적 횟수"로 (§S-8.2)
9. 챌린지 생성에서 정원 입력 제거(10 고정), 인증 방식 3종 제한, GPS 필수화 (§S-4.3)
10. 코인 내역 사유 한글 매핑 (§S-7.1)
11. 응답 래퍼가 축마다 다름 — A축 raw / B축 `{success,data}` (§A-1.2)

---

## 11. API 계약 (실제 구현 37개)

> 여기에 없는 경로는 구현돼 있지 않다 — 호출하면 404다.
> 섹션 번호는 `A-` 접두어를 쓴다.

## A-1. 공통 규칙

### A-1.1 Base URL

```
http://localhost:8080/api
```

### A-1.2 ⚠️ 응답 형태가 축마다 다르다

**성공 응답에 통일된 래퍼가 없다.** 축별로 별도 개발되며 갈렸고, 통일은 아직 하지 않았다.
클라이언트는 엔드포인트마다 어느 쪽인지 알고 파싱해야 한다.

**A축·인증·사용자 — 래퍼 없음 (raw)**

```json
{ "date": "2026-08-27", "status": "SUCCESS", "currentStreak": 5 }
```

`/api/auth/*` · `/api/users/me*`(challenges 제외) · `/api/personal/*` · `/api/dashboard/*`

**B축 팀 챌린지 — `{success, data}` 래핑**

```json
{ "success": true, "message": null, "data": { "id": 1, "title": "..." } }
```

`/api/challenges/*` · `/api/teams/*` · `/api/users/me/challenges` · `/api/verification-submissions/*`

### A-1.3 에러 응답 — 이건 전부 동일

```json
{ "success": false, "message": "등록된 위치에서 2224m 떨어져 있습니다. (허용 50m)", "errorCode": "GPS_OUT_OF_RANGE" }
```

`errorCode` 로 분기하고 `message` 는 그대로 노출해도 되도록 작성돼 있다.

### A-1.4 상태 코드

| 코드 | 의미 |
|---|---|
| 200 / 201 / 204 | 성공 |
| 400 | 검증 실패, GPS 범위 밖, 잔액 부족, 위치 미등록 |
| 401 | 토큰 없음·만료·**탈퇴 계정** |
| 403 | 권한 없음 (남의 리소스) |
| 404 | 리소스 없음, **미매핑 경로** |
| 409 | 상태 충돌 (중복 인증, 중복 참가, 정원 초과) |
| 413 | 업로드 10MB 초과 |
| 415 | 지원하지 않는 이미지 형식 |
| 500 | AI 판정 **계약 오류** — 대부분 `category` 가 `EXERCISE`/`STUDY` 가 아닐 때 (§A-8 category) |
| 502 | AI 서비스 통신 실패·타임아웃·upstream 5xx |

### A-1.5 인증

```
Authorization: Bearer {accessToken}
```

- `/api/auth/signup`, `/api/auth/login` 을 제외한 **전 경로가 JWT 필수**
- **가입 응답에 토큰이 포함된다** — 가입 직후 로그인을 다시 호출하지 말 것
  (BCrypt가 두 번 돌아 체감 지연이 2배가 된다)
- 만료 24시간
- 서버는 매 요청 `is_active` 를 확인한다. **탈퇴 시 기존 토큰도 즉시 401**

---

## A-2. 전체 목록 (37개)

### 인증 (3)

| 메서드 | 경로 | 설명 |
|---|---|---|
| POST | `/api/auth/signup` | 가입 (토큰 포함 반환) |
| POST | `/api/auth/login` | 로그인 |
| POST | `/api/auth/logout` | 로그아웃 (무상태, 클라이언트가 토큰 파기) |

### 사용자 (4)

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/api/users/me` | 마이페이지 |
| DELETE | `/api/users/me` | 회원 탈퇴 (soft delete) |
| GET | `/api/users/me/coins` | 코인 내역 (페이징) |
| GET | `/api/dashboard/home` | 홈 대시보드 |

### A축 — 개인 습관 (10)

| 메서드 | 경로 | 설명 |
|---|---|---|
| POST | `/api/users/me/location` | 인증 위치 등록 |
| GET | `/api/users/me/location` | 인증 위치 조회 |
| PUT | `/api/users/me/location` | 인증 위치 수정 |
| POST | `/api/personal/check-in` | 개인 인증 |
| GET | `/api/personal/check-in/today` | 오늘 인증 상태 |
| POST | `/api/personal/check-in/{checkInId}/ai-verification` | 사진 업로드 (AI 확정) |
| GET | `/api/personal/weekly-goal` | 주간 목표·구제권 현황 |
| PUT | `/api/personal/weekly-goal` | 목표 변경 예약 / 인증 방식 변경 |
| POST | `/api/personal/recovery-tickets` | **구제권 구매 (상점)** |
| POST | `/api/personal/rescue` | **구제 대기 주 사후 구매** |

### B축 — 팀 챌린지 (20)

| 메서드 | 경로 | 설명 |
|---|---|---|
| POST | `/api/challenges` | 챌린지 생성 (방장 자동 참가) |
| GET | `/api/challenges` | 공개 챌린지 검색 |
| GET | `/api/challenges/{id}` | 챌린지 상세 |
| GET | `/api/challenges/invite/{code}` | 초대 코드 조회 |
| GET | `/api/users/me/challenges` | 내 참여 챌린지 |
| POST | `/api/challenges/{id}/participants` | 참가 신청 |
| GET | `/api/challenges/{id}/participants` | 참가자 목록 (`?status=PENDING`) |
| POST | `/api/challenges/{id}/participants/{participantId}/approve` | 방장 승인 |
| DELETE | `/api/challenges/{id}/participants/{userId}` | 참가 취소 |
| GET | `/api/challenges/{id}/teams` | 팀 목록 |
| POST | `/api/challenges/{id}/check-ins` | 팀 챌린지 인증 |
| GET | `/api/challenges/{id}/check-ins` | 인증 목록 |
| GET | `/api/challenges/{id}/team-detail` | 팀 상세 (vs 상대팀) |
| POST | `/api/verification-submissions/{submissionId}/ai-verification` | 사진 업로드 (AI 확정) |
| GET | `/api/challenges/{id}/result` | 정산 결과 |
| GET | `/api/challenges/{id}/leaderboards` | 리더보드 |
| POST | `/api/challenges/{id}/cheers` | 응원 |
| GET | `/api/teams/{teamId}/chat` | 채팅 조회 |
| POST | `/api/teams/{teamId}/chat` | 채팅 전송 |
| DELETE | `/api/teams/{teamId}/chat/{messageId}` | 채팅 삭제 |

---

## A-3. Auth API

### POST /api/auth/signup

```json
{ "email": "user@test.com", "password": "password1234", "nickname": "부스터" }
```

**201** (raw)

```json
{
  "userId": 1, "email": "user@test.com", "nickname": "부스터",
  "coinBalance": 500, "joinedAt": "2026-08-27T10:00:00+09:00",
  "accessToken": "eyJhbGciOiJIUzUxMiJ9..."
}
```

가입 보너스 **500코인**과 무료 구제권 1개가 함께 지급된다.
`DUPLICATE_EMAIL` (409) — 동시 가입 경합도 409로 정규화된다.

### POST /api/auth/login

```json
{ "email": "user@test.com", "password": "password1234" }
```

**200** → `userId`, `email`, `nickname`, `accessToken`
`INVALID_CREDENTIALS` (401) — 이메일 존재 여부를 구분해 알려주지 않는다(계정 열거 방지).

---

## A-4. Users API

### GET /api/users/me

**200** (raw) — `userId`, `email`, `nickname`, `joinedAt`, `totalAttendance`, `coinBalance`

### GET /api/users/me/coins?page=0&size=20

**200** (raw)

```json
{
  "transactions": [
    { "type": "STREAK_REWARD", "amount": 100, "balanceAfter": 600, "createdAt": "..." }
  ],
  "totalCount": 42
}
```

`size` 상한 100. 잘못된 `page`/`size` 는 클램프된다(500 안 남).

> ⚠️ **`POST /api/users/me/coins` 는 없고, 만들지 않는다.**
> 클라이언트가 잔액을 임의로 조작할 수 있게 되기 때문이다. 코인은 서버 이벤트로만 움직인다.
> 상점 구매는 §A-6 참조.

### DELETE /api/users/me

**204**. soft delete(`is_active=false`). 이후 기존 토큰도 401.

### GET /api/dashboard/home

**200** (raw)

```json
{
  "coinBalance": 1500,
  "streak": { "current": 12, "max": 30 },
  "weeklySuccessCount": 2,
  "todayStatus": "NOT_CHECKED",
  "calendar": { "year": 2026, "month": 8, "days": [ { "date": "2026-08-01", "status": "SUCCESS" } ] }
}
```

---

## A-5. A축 — 개인 습관

### A-5.1 POST /api/users/me/location

```json
{ "lat": 37.5665, "lng": 126.9780, "radiusMeters": 50, "placeName": "집" }
```

**201** (raw). 이미 있으면 `LOCATION_ALREADY_REGISTERED` (409) → `PUT` 사용.

> ⚠️ `radiusMeters` 에 **상한이 없다**(`> 0` 만 검사). 미해결 항목.

### A-5.2 POST /api/personal/check-in

```json
{ "lat": 37.5665, "lng": 126.9780 }
```

**201**. 응답 본문은 인증 방식에 따라 갈린다.

**GPS** — 즉시 확정

```json
{
  "date": "2026-08-27", "status": "SUCCESS", "verifiedAt": "2026-08-27T10:00:00+09:00",
  "currentStreak": 13, "maxStreak": 30, "coinBalance": 1600,
  "rewardGranted": true, "checkInId": 42
}
```

**AI / GPS_PHOTO_AI** — 사진 대기

```json
{ "date": "2026-08-27", "status": "PENDING", "verifiedAt": null,
  "currentStreak": 12, "maxStreak": 30, "coinBalance": 1500,
  "rewardGranted": false, "checkInId": 43 }
```

`checkInId` 는 **사진 업로드(§A-5.4)의 입력**이다. 이게 없으면 AI 인증을 시작할 수 없다.

| 에러 | 코드 | 상황 |
|---|---|---|
| 400 | `LOCATION_NOT_REGISTERED` | 위치 미등록 |
| 400 | `GPS_OUT_OF_RANGE` | 범위 밖. **레코드를 만들지 않으므로 그날 재시도 가능** |
| 409 | `DUPLICATE_CHECK_IN` | 오늘 이미 인증 완료 |
| 409 | `CHECK_IN_AWAITING_PHOTO` | 사진 대기 중 |

### A-5.3 GET /api/personal/check-in/today

**200** → `{ "date": "...", "status": "SUCCESS|PENDING|NOT_CHECKED", "verifiedAt": ... }`

### A-5.4 POST /api/personal/check-in/{checkInId}/ai-verification

`multipart/form-data` — `image`(파일), `category`(문자열)

> ⚠️ **`category` 는 `EXERCISE` 또는 `STUDY` 만 가능하다.** `ai-service` 가 이 둘만 받는 Enum이라
> 다른 값을 보내면 422를 돌려주고, 백엔드는 그것을 **500 `AI_VERIFICATION_500`**("AI 판정 계약 오류")
> 으로 바꾼다. 백엔드는 이 값을 검증하지 않고 그대로 전달한다.
> **개인 트랙에는 카테고리를 저장하는 곳이 없어 클라이언트가 매번 지정해야 한다** (§A-13 미해결).

**201** (raw)

```json
{
  "date": "2026-08-27", "passed": true, "confidenceScore": 0.93,
  "detectedLabels": ["gym", "dumbbell"], "reason": null, "modelName": "claude-...",
  "currentStreak": 13, "coinBalance": 1600, "rewardGranted": true
}
```

- 업로드 상한 **10MB** (초과 413), `image/jpeg` · `image/png` · `image/webp` (그 외 415)
- **거절 시(`passed:false`) 체크인 레코드를 삭제한다** — PENDING이 하루를 점유해 재시도가 막히는 것을 방지
- 403 `NOT_CHECK_IN_OWNER` / 409 `CHECK_IN_ALREADY_CONFIRMED` / 502 `AI_VERIFICATION_502`
- 502가 나도 체크인은 PENDING으로 남아 재시도할 수 있다

### A-5.5 GET /api/personal/weekly-goal

**200** (raw) — **상점의 보유 수량·가격 조회처이기도 하다.**

```json
{
  "weekStart": "2026-08-24", "targetDays": 3, "pendingTargetDays": null,
  "successCount": 2, "remainingDays": 4,
  "recoveryTickets": 3, "freeTickets": 1, "paidTickets": 2,
  "ticketPrice": 800, "coinBalance": 1500,
  "verificationType": "GPS", "lastWeekResult": "ACHIEVED",
  "pendingRescueWeek": null, "rescueDeadline": null, "lateRescuePrice": 1200
}
```

| 필드 | 용도 |
|---|---|
| `freeTickets` / `paidTickets` | 무료분은 **월말 소멸**, 구매분은 영구. 앱이 구분해 안내 |
| `ticketPrice` | **상점 표시 가격.** 앱에 하드코딩하지 말 것 |
| `pendingRescueWeek` + `rescueDeadline` | **null이 아니면 구제 안내 팝업**을 띄운다 |
| `lateRescuePrice` | 그 팝업의 결제 금액 |

400 `LOCATION_NOT_REGISTERED` — 위치 등록 전에는 조회 불가.

### A-5.6 PUT /api/personal/weekly-goal

```json
{ "targetDays": 5, "verificationType": "AI" }
```

- `targetDays` 2~7 필수. **다음 달 1일에 반영**되며 응답의 `pendingTargetDays` 로 확인
- `verificationType` 선택. `GPS` / `AI` / `GPS_PHOTO_AI` 만 허용, **즉시 반영**
- 400 `UNSUPPORTED_VERIFICATION_TYPE`

### A-5.7 POST /api/personal/recovery-tickets — 구제권 구매

요청 본문 없음.

**201** (raw)

```json
{ "recoveryTickets": 4, "price": 800, "coinBalance": 700 }
```

- 400 잔액 부족 (차감되지 않음)
- 구매 한도 없음
- `coin_transactions` 에 `RECOVERY_TICKET_PURCHASE` 로 기록

### A-5.8 POST /api/personal/rescue — 사후 구매

요청 본문 없음. 구제 대기 중인 주를 **1,200코인**으로 즉시 구제한다.

**200** → `WeeklyGoalResponse` (§A-5.5와 동일 형태)

- 404 `NO_PENDING_RESCUE` — 구제 대기 중인 주 없음
- 400 `RESCUE_DEADLINE_PASSED` — 기한 경과
- 400 잔액 부족

---

## A-6. 상점

**상점 전용 API는 없다.** 파는 물건이 구제권 하나이고 이미 도메인 API가 있어,
상품·주문 테이블을 만들지 않기로 했다. 설계 근거는 `docs/project-plan.md` §A-6.

| 상점 동작 | 호출 |
|---|---|
| 카탈로그 | 앱이 보유. **가격만** `GET /api/personal/weekly-goal` → `ticketPrice` 로 덮어쓴다 |
| 구제권 구매 | `POST /api/personal/recovery-tickets` |
| 보유 수량 | `GET /api/personal/weekly-goal` → `freeTickets` / `paidTickets` |
| 구제권 "사용" | **없다.** 주간 채점이 자동 소모한다 |
| 구제 대기 중 즉시 구제 | `POST /api/personal/rescue` |
| 기프티콘 | 판매하지 않음 (`purchasable=false`) |

**지켜야 할 것**

1. **코인을 직접 움직이는 API를 쓰지 않는다.** `POST /api/users/me/coins` 는 없고 만들지 않는다
2. **보유 수량을 기기에 저장하지 않는다.** 서버가 단일 진실 원천이다
3. **구제권에 "사용" 버튼을 만들지 않는다.** 사용자가 쓰는 물건이 아니라 미달 시 자동 소모된다

---

## A-7. B축 — 챌린지

> 이하 전부 `{success, data}` 래핑.

### A-7.1 POST /api/challenges

```json
{
  "category": "EXERCISE", "title": "아침 운동", "description": "...",
  "verificationType": "GPS", "durationDays": 7, "depositCoins": 100,
  "visibility": "PUBLIC", "approvalType": "AUTO", "maxParticipants": 10,
  "gpsLat": 37.5665, "gpsLng": 126.9780, "gpsRadiusMeters": 50, "gpsPlaceName": "공원"
}
```

- **`maxParticipants` 는 10 고정** (다른 값은 400)
- **`verificationType` 은 `GPS`/`AI`/`GPS_PHOTO_AI` 만** (`PHOTO`·`GPS_PHOTO` 는 400)
- **GPS 좌표 필수** — 방장이 곧바로 참가자가 되므로. 생략하면 개인 인증 위치를 재사용하고,
  둘 다 없으면 400 `LOCATION_REQUIRED`
- **방장은 CONFIRMED 참가자가 되고 예치금이 차감된다**

**201** → `id`, `title`, `status`("READY"), `inviteCode`, `maxParticipants`, `createdBy`, `joined` …

### A-7.2 GET /api/challenges?category=&keyword=&page=&size=

공개 + `READY` 챌린지 검색. 각 항목에 `joined`(내 참여 여부) 포함.

### A-7.3 GET /api/users/me/challenges

내가 참여 중인 챌린지. 앱 재시작 후 복원용.

### A-7.4 POST /api/challenges/{id}/participants

```json
{ "personalStatement": "...", "gpsLat": 37.5665, "gpsLng": 126.9780, "gpsRadiusMeters": 50, "gpsPlaceName": "공원" }
```

**201** → `ParticipantResponse` (`id` = participantId, `userId`, `teamId`, `status`, …)

- 409 `ALREADY_APPLIED` / 정원 초과 / `CHALLENGE_ALREADY_STARTED`
- **10명이 차면 서버가 5:5 자동 편성 + 자동 시작**(READY → ACTIVE)

> ⚠️ `gpsRadiusMeters` 에 `@Positive` 검증이 없어 음수·0이 400이 아닌
> **409 `DATA_CONFLICT`** 로 나간다(DB CHECK가 대신 막음). 미해결 항목.

### A-7.5 GET /api/challenges/{id}/participants?status=PENDING

참가자 목록. **방장 승인 화면이 `participantId`(= `data[].id`)를 얻는 유일한 경로다.**

### A-7.6 POST /api/challenges/{id}/participants/{participantId}/approve

방장만 호출 가능. `LEADER` 승인 방식 챌린지용.

### A-7.7 POST /api/challenges/{id}/check-ins

```json
{ "currentLat": 37.5665, "currentLng": 126.9780 }
```

> 필드명이 A축(`lat`/`lng`)과 다르다. **B축은 `currentLat`/`currentLng`.**

**201**

```json
{ "success": true, "data": {
  "id": 1, "participantId": 7, "checkInDate": "2026-08-27",
  "status": "SUCCESS", "verifiedAt": "...", "submissionId": 15 } }
```

`submissionId` 는 **사진 업로드(§A-7.8)의 입력**이다.

- 400 `GPS_OUT_OF_RANGE` — **A축과 동일하게 즉시 거절 + 거리 안내.** FAILED 레코드를 만들지 않는다
- 409 `CHALLENGE_NOT_ACTIVE` / `TEAM_NOT_ASSIGNED`
- 같은 날 재호출은 **멱등 반환**(기존 기록을 그대로 돌려준다)

### A-7.8 POST /api/verification-submissions/{submissionId}/ai-verification

`multipart/form-data` — `image`, `category`. **201**. 제약은 §A-5.4와 동일(10MB, jpeg/png/webp).

> ⚠️ `category` 는 여기서도 **`EXERCISE` / `STUDY` 만** 유효하다.
> 챌린지의 `category` 는 자유 문자열이라 그 값을 그대로 넘기면 **500**이 난다 (§A-13 미해결).

### A-7.9 그 외

| 경로 | 설명 |
|---|---|
| `GET /api/challenges/{id}/teams` | 팀 목록 + 참여율 |
| `GET /api/challenges/{id}/team-detail` | 내 팀 vs 상대팀 |
| `GET /api/challenges/{id}/check-ins` | 인증 목록 |
| `GET /api/challenges/{id}/result` | 정산 결과 (WIN/LOSE/DRAW, 지급 코인) |
| `GET /api/challenges/{id}/leaderboards?type=` | 리더보드 |
| `POST /api/challenges/{id}/cheers` | 응원 이모지 |
| `GET`·`POST` `/api/teams/{teamId}/chat` | 팀 채팅 (멤버만) |
| `DELETE /api/teams/{teamId}/chat/{messageId}` | 본인 메시지 삭제 |

---

## A-8. 상태값 정의

### challenge_status

| 값 | 의미 |
|---|---|
| `READY` | 모집 중 |
| `ACTIVE` | 진행 중 (정원 충족 시 자동 전환) |
| `ENDED` | 종료 |
| `CANCELLED` | 취소 |

### personal_check_in_status (A축)

| 값 | 의미 |
|---|---|
| `SUCCESS` | 확정 |
| `PENDING` | AI 사진 대기 |

"그날 안 함"은 **레코드 부재**로 표현한다. 조회 시에만 `NOT_CHECKED` 로 내려간다.

### check_in_status (B축)

`PENDING` / `SUCCESS` / `FAILED`
— GPS 실패는 400으로 거절하므로 `FAILED` 는 AI 거절 경로에서만 생긴다.

### verification_type

| 값 | 지원 |
|---|---|
| `GPS` | ✅ |
| `AI` | ✅ |
| `GPS_PHOTO_AI` | ✅ |
| `PHOTO` / `GPS_PHOTO` | ❌ DB enum에는 있으나 **생성 단계에서 400** |

### weekly_evaluation_result (A축)

| 값 | 의미 |
|---|---|
| `ACHIEVED` | 목표 달성 |
| `RESCUED` | 구제권 소모 또는 사후 구매로 구제 |
| `PENDING_RESCUE` | 미달 + 구제권 없음. **유예 중** |
| `FAILED` | 유예 기한 경과. 스트릭 0 + 코인 차감 |

### participant_status

`PENDING` / `CONFIRMED` / `REJECTED` / `CANCELLED` / `LEFT`

### category ⚠️ 두 개의 서로 다른 `category` 가 있다

| 쓰이는 곳 | 값 | 검증 |
|---|---|---|
| `challenges.category` (챌린지 분류) | **자유 문자열** | `@NotBlank` 뿐 |
| AI 인증 요청의 `category` | **`EXERCISE` / `STUDY` 만** | `ai-service` Pydantic Enum (그 외 422) |

**이름이 같지만 값 집합이 다르다.** 챌린지 카테고리를 AI 요청에 그대로 넘기면
`EXERCISE`/`STUDY` 가 아닌 순간 502가 난다.

당분간의 안전한 사용법:

- 챌린지를 만들 때 **`AI`·`GPS_PHOTO_AI` 를 고르면 카테고리를 `EXERCISE`/`STUDY` 로 제한**한다
- 개인 트랙은 저장소가 없으므로 앱이 사용자에게 한 번 묻고 로컬에 기억하거나,
  업로드 화면에서 매번 고르게 한다

---

## A-9. 주요 errorCode

| 코드 | 상태 | 상황 |
|---|---|---|
| `DUPLICATE_EMAIL` | 409 | 가입 중복 |
| `INVALID_CREDENTIALS` | 401 | 로그인 실패 |
| `INACTIVE_USER` | 403 | 탈퇴 계정 (필터에서 401로 끊기는 경우가 더 많음) |
| `LOCATION_NOT_REGISTERED` | 400 | 인증 위치 미등록 |
| `LOCATION_ALREADY_REGISTERED` | 409 | 이미 등록됨 → PUT 사용 |
| `LOCATION_REQUIRED` | 400 | 챌린지 생성 시 방장 위치 없음 |
| `GPS_OUT_OF_RANGE` | 400 | 인증 범위 밖 (A·B 공통) |
| `DUPLICATE_CHECK_IN` | 409 | 오늘 이미 인증 |
| `CHECK_IN_AWAITING_PHOTO` | 409 | 사진 대기 중 |
| `CHECK_IN_ALREADY_CONFIRMED` | 409 | 확정된 체크인에 재업로드 |
| `NOT_CHECK_IN_OWNER` | 403 | 남의 체크인 |
| `NO_PENDING_RESCUE` | 404 | 구제 대기 주 없음 |
| `RESCUE_DEADLINE_PASSED` | 400 | 구제 기한 경과 |
| `UNSUPPORTED_VERIFICATION_TYPE` | 400 | 미지원 인증 방식 |
| `ALREADY_APPLIED` | 409 | 중복 참가 |
| `CHALLENGE_NOT_ACTIVE` | 409 | 진행 중이 아님 |
| `CHALLENGE_ALREADY_STARTED` | 409 | 이미 시작됨 |
| `TEAM_NOT_ASSIGNED` | 409 | 팀 배정 전 인증 시도 |
| `TEAMS_NOT_FORMED` | 409 | 편성 전 조회 |
| `VALIDATION_ERROR` | 400 | 요청 검증 실패 |
| `MALFORMED_REQUEST` | 400 | 본문 파싱 실패 |
| `DATA_CONFLICT` | 409 | DB 제약 위반 (검증 누락 경로) |
| `AI_VERIFICATION_502` | 502 | AI 서비스 통신 실패·타임아웃·upstream 5xx |
| `AI_VERIFICATION_500` | 500 | AI 판정 **계약 오류** (upstream 4xx). 대부분 `category` 가 `EXERCISE`/`STUDY` 가 아닐 때 |

---

## A-10. 스케줄러 (앱이 호출하지 않음)

앱에서 트리거할 수 없지만 **상태가 저절로 바뀌는 지점**이라 클라이언트가 알아야 한다.

| 시각 (KST) | 작업 | 앱에 보이는 변화 |
|---|---|---|
| 매주 월 00:01 | 지난주 채점 | `lastWeekResult` 갱신, `pendingRescueWeek` 발생 가능 |
| 매일 00:10 | 구제 유예 만료 | `PENDING_RESCUE` → `FAILED`, 스트릭 0 + 코인 −500 |
| 매월 1일 00:05 | 무료 구제권 지급 + 목표 예약 반영 | `freeTickets` = 1, `pendingTargetDays` → `targetDays` |
| 1분 주기 | 챌린지 종료 처리 | `status` → `ENDED`, 정산 |

앱은 홈 진입 시 `GET /api/personal/weekly-goal` 을 호출해 `pendingRescueWeek` 을 확인하고,
값이 있으면 안내 팝업을 띄운다.

---

## A-11. AI 인증 2단계 흐름 요약

```
A축   POST /api/personal/check-in            → status=PENDING, checkInId
      POST /api/personal/check-in/{checkInId}/ai-verification   (multipart)
      → passed=true  : 확정, 스트릭 +1
        passed=false : 체크인 삭제 (그날 재시도 가능)

B축   POST /api/challenges/{id}/check-ins    → status=PENDING, submissionId
      POST /api/verification-submissions/{submissionId}/ai-verification
```

`ai-service` 는 `docker compose --profile ai up -d` 로 기동한다. 없으면 502.

---

## A-12. 이전 판에서 사라진 API

옛 문서를 보고 구현했다면 아래는 **전부 404**다.

| 이전 경로 | 현재 |
|---|---|
| `POST /api/teams` (팀 생성) | **없음.** 정원 충족 시 서버가 자동 편성 |
| `GET /api/teams/{id}` · `POST/DELETE /api/teams/{id}/members` | **없음.** `GET /api/challenges/{id}/teams` |
| `GET /api/users/{userId}/teams` | **없음** |
| `POST /api/teams/{teamId}/challenges` | **`POST /api/challenges`** |
| `GET /api/teams/{teamId}/challenges` | **`GET /api/challenges`** (검색) |
| `GET /api/users/{userId}/check-ins` | **없음** |
| `GET /api/users/{userId}` · `PATCH /api/users/{userId}` | **`/api/users/me`** |
| `POST /api/check-ins/{id}/verification-submissions` | **없음.** 체크인이 제출까지 생성 |
| `GET /api/check-ins/{id}/verification-submissions` | **삭제.** 실패 사유를 400 본문으로 즉시 주므로 불필요 |
| `POST /api/check-ins/{id}/recovery-missions` | **삭제.** 복귀 미션 폐지 |
| `GET /api/users/{userId}/recovery-missions` | **삭제** |
| `PATCH /api/recovery-missions/{id}` | **삭제** |
| `GET /api/personal/recovery/status` · `POST /api/personal/recovery` | **삭제.** 앱에 호출부가 남아 있다 |
| `GET/PATCH /api/users/{userId}/notifications` | **미구현** (Phase 2) |
| `GET/PATCH /api/users/{userId}/settings` | **미구현** (Phase 2) |

---

## A-13. 미해결 항목

| 항목 | 영향 |
|---|---|
| **AI `category` 가 검증되지 않음** | `ai-service` 는 `EXERCISE`/`STUDY` 만 받는데 백엔드가 검증 없이 전달 → 잘못된 값이 **500**으로 나온다(사용자 입력 오류가 서버 장애로 집계됨) |
| **개인 트랙에 카테고리 저장소 없음** | `personal_locations` 에 컬럼이 없어 클라이언트가 업로드마다 카테고리를 지정해야 한다 |
| **챌린지 `category` 가 자유 문자열** | `category:"독서"` + `verificationType:"AI"` 로 챌린지를 만들 수 있고, 생성·참여·체크인까지 통과한 뒤 **사진 업로드 단계에서 500**이 난다 |
| 응답 래퍼가 축마다 다름 | 클라이언트가 엔드포인트별로 파싱 분기 |
| GPS 반경 상한 없음 | 반경을 크게 잡으면 어디서나 인증 통과 (A·B 공통) |
| 참가 API `gpsRadiusMeters` 검증 누락 | 400 대신 409 `DATA_CONFLICT` |
| 주간 목표 스케줄러에 분산락 없음 | 멀티 인스턴스에서 중복 실행 |
| 구제 만료에 DB 멱등 방어 없음 | 벌칙 중복 적용 가능 |

---

## 12. 파트별 정렬 필요 항목

### 프론트

화면 단위 상세는 **§10 화면 명세** 에 있다 (5탭 구조 · 화면 전이도 ·
화면별 호출 API · 37개 API의 화면 매핑 · 정렬 체크리스트).

**P0 — 지금 깨져 있다**

- [ ] `recovery_service.dart` · `models/recovery.dart` **삭제** — `/api/personal/recovery/status`,
      `/api/personal/recovery` 는 삭제된 경로라 홈·인증 화면이 현재 **404를 받고 있다**
- [ ] **상점을 서버 API로 전환** (§6.4) — 가격 800, 로컬 인벤토리 제거, "사용" 버튼 제거
- [ ] **구제 안내 팝업** — `pendingRescueWeek` 이 있을 때. 없으면 유예 기능 자체가 무의미하다

**P1 — 서버에 있는데 화면이 없다**

- [ ] **주간 목표 화면** — A축 핵심(목표·진행률·구제권)인데 볼 방법이 없다
- [ ] **AI 사진 업로드** — 없으면 개인·팀 모두 AI 인증을 실제로 못 쓴다.
      업로드 시 **`category` 를 `EXERCISE`/`STUDY` 중에서** 보내야 한다 (§4.1)
- [ ] `GET /api/users/me/challenges` 로 참여 챌린지 복원 (현재 로컬 보관 → 재설치 시 유실)
- [ ] **방장 승인 화면** — `LEADER` 승인 챌린지가 작동 불가

**P2 — 정합성**

- [ ] 스트릭 문구 "7일 연속" → **"7회마다"** (연속 일수가 아니라 누적 횟수)
- [ ] 챌린지 생성: 정원 입력 제거(10 고정) · 인증 방식 3종 제한 · **GPS 좌표 필수** ·
      **AI 계열 선택 시 카테고리를 `EXERCISE`/`STUDY` 로 제한** (§4.1)
- [ ] **응답 형태가 축마다 다르다** — A축은 raw JSON, B축은 `{success, data}` 래핑
      (§11 API 계약 §1.2). 통일은 별도 과제

### AI 서비스

> **결론: 이번 릴리스에서 ai-service 는 고칠 게 없다.**
> 계약(`POST /verify`, multipart `category`+`image`)이 그대로고, 개인 트랙이 같은
> `AiVerificationClient` 를 재사용한다. 아래는 **작업 지시가 아니라 알아둘 것**이다.

**① 카테고리는 `EXERCISE` / `STUDY` 2개로 확정** (결정 완료 — ai-service 변경 없음)

앱 카테고리 4개 중 3개가 기존 2개로 덮이고(§4.1), `기상` 만 **AI 인증 대상에서 제외**한다.
`ai-service` 는 손대지 않는다.

| 앱 카테고리 | 처리 |
|---|---|
| 운동 | `EXERCISE` |
| 공부 | `STUDY` |
| 독서 | `STUDY` — 프롬프트에 활자책 독서가 통과 기준으로 이미 있다 |
| **기상** | **AI 인증 불가.** GPS 전용으로 둔다 |

> **출처 메모**: 앱의 카테고리 4종(kms224, 08-09)과 ai-service 의 2종(김태훈, 08-08)은
> **각자 독립적으로 정해졌고 합의 기록이 없다.** 옛 `MVP_API_SPEC.md` 에는 `category` 가
> 언급조차 없었다. 이 표가 최초의 합의본이다.

**② 개인 습관도 AI를 쓰게 됐다** (알아둘 것 — 작업 아님)

V16에서 A축에 AI 인증이 추가돼 **호출 경로가 둘로 늘었다.** `AiVerificationClient` 를
재사용하므로 ai-service 계약·구현 변경은 없다.

개인 트랙의 인증 방식 기본값이 `GPS` 라 **사용자가 직접 바꿔야 쓰는 옵트인**이다.
당장 호출이 급증하지는 않지만, 개인 습관에서 AI를 택하는 사용자가 늘면
Anthropic 비용·레이트리밋이 먼저 걸리는 지점이 된다. 상세는 `docs/api/AI_SERVICE_SPEC.md` §8.6.

**③ 시연 전 기동 확인** (운영)

`ai-service` 는 opt-in 프로필이다 — `docker compose --profile ai up -d`.
안 띄우면 AI 인증이 전부 502다. `ai-service/.env` 의 `ANTHROPIC_API_KEY` 도 함께 확인.

### 백엔드 (남은 것)

- [ ] `WeeklyGoalScheduler` 에 `@SchedulerLock` 없음 — 멀티 인스턴스에서 중복 실행
- [ ] 구제 만료(`expireOverdueRescues`)에 DB 멱등 방어 없음 — 이중 처벌 가능
- [ ] GPS 반경 상한 없음 — 반경을 크게 잡으면 어디서나 인증 통과 (개인·팀 공통)
- [ ] 참가 API `gpsRadiusMeters` 검증 누락 → 400 대신 409 반환
- [ ] **AI `category` 검증 없음** (§4.1) — `EXERCISE`/`STUDY` 외 값이 500으로 나간다.
      생성 단계에서 막는 게 맞다(인증 방식과 같은 방식). 지금은 앱이 대신 막아야 한다
- [ ] **개인 트랙 카테고리 저장소 없음** — `personal_locations` 에 컬럼을 추가할지 **토요일(08-29) 논의**.
      ① 앱이 업로드마다 지정 (지금 그대로, 추가 작업 0) ② `V17` 로 컬럼 추가 + `PUT /weekly-goal` 에 필드 추가.
      일정상 ①로 가고 나중에 ②로 옮기는 것을 권한다

---

## 13. 관련 문서

| 문서 | 내용 |
|---|---|
| §11 API 계약 | **API 계약** (실제 구현 37개) |
| §10 화면 명세 | **화면 명세** (5탭·전이도·화면별 API·정렬 체크리스트) |
| `docs/erd/MVP_ERD.md` | 테이블 상세 |
| `backend/src/main/resources/db/migration/` | V1~V16 마이그레이션 |
| `monitoring/README.md` | 부하·버그 관측 도구 |
| `docs/backend/*-retro.md` | 문제 해결 회고 (당시 기록이므로 갱신 대상 아님) |
