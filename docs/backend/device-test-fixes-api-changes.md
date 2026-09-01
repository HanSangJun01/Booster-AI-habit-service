# 실기기 테스트 피드백 — 백엔드 수정과 API 변경

2026-09-01 실기기 테스트에서 나온 지적 19건 중 **백엔드 몫 13건**을 처리했다.
프론트가 맞춰야 하는 변경을 먼저 적고, 그다음 내부 수정을 적는다.

브랜치: `integration/backend-frontend`
마이그레이션: **V17**(위치 변경 예약), **V18**(개인 목표 카테고리)

---

## 1. 프론트가 반드시 맞춰야 하는 것

### 1.1 챌린지 생성 — 값이 좁아졌다

| 필드 | 이전 | 지금 |
|---|---|---|
| `category` | 자유 문자열 | **`EXERCISE` \| `STUDY`** 만. 그 외 400 |
| `verificationType` | `GPS` \| `AI` \| `GPS_PHOTO_AI` | **`GPS_PHOTO_AI`** 만. 그 외 400 |
| `depositCoins` | 0 이상 | **100 이상**. 미만이면 400 |
| `gpsRadiusMeters` | 양수면 통과 | **10 ~ 1000**. 벗어나면 400 |
| `title` | 필수 | **선택**. 비우면 서버가 `"운동 · 김부스터"` 로 만든다 |

`title` 을 더 이상 입력받지 않기로 했으므로, 앱은 이 필드를 **보내지 않으면 된다**.
목록에는 카테고리와 방장 닉네임이 함께 보인다.

### 1.2 참가 신청 응답에 `coinBalance` 가 생겼다

`POST /api/challenges/{id}/participants` 응답:

```json
{ "id": 12, "challengeId": 3, "userId": 7, "status": "CONFIRMED",
  "coinBalance": 400 }
```

**앱은 이 값으로 세션 코인을 갱신해야 한다.** 지금은 응답에 잔액이 없어서 참가해도 화면의
코인이 그대로였고, 재로그인해야 차감된 것처럼 보였다.

```dart
// participant_service.dart apply() 안
final balance = data['coinBalance'];
if (balance != null) Session.coinBalance = balance;
```

### 1.3 위치 변경(PUT)이 즉시 반영되지 않는다

`PUT /api/users/me/location` 은 이제 **예약**이다. 다음 달 1일에 반영된다.
응답에 `pending*` 이 추가됐다:

```json
{ "lat": 37.5, "lng": 127.0, "radiusMeters": 100, "placeName": "집",
  "pendingLat": 37.6, "pendingLng": 127.1,
  "pendingRadiusMeters": 200, "pendingPlaceName": "새 헬스장" }
```

- `lat`/`lng`/`radiusMeters` — **지금 인증에 쓰이는** 값
- `pending*` — 다음 달 1일부터 적용될 값 (없으면 null)

화면에 둘 다 보여줘야 한다. 안 그러면 "바꿨는데 왜 그대로지?" 가 된다.
지금 값과 **똑같은 좌표·반경**을 보내면 예약이 취소된다("역시 그대로 둘래").

최초 등록(`POST`)은 예전처럼 즉시 반영된다.

### 1.4 주간 목표에 `category` 가 생겼다

`PUT /api/personal/weekly-goal` 요청에 추가 가능:

```json
{ "targetDays": 5, "verificationType": "GPS_PHOTO_AI", "category": "EXERCISE" }
```

`GET /api/personal/weekly-goal` 응답에도 `category` 가 담긴다.

온보딩을 **개인목표(운동/공부) → GPS 설정** 순서로 바꾸면, 앞 단계에서 고른 값을 여기에 넣으면 된다.
AI 사진 인증(`POST .../ai-verification`)의 `category` 폼 필드는 이 값을 그대로 보내면 된다.

개인 트랙도 `verificationType` 은 `GPS_PHOTO_AI` 만 받는다.

### 1.5 새 API — 챌린지 취소

```
DELETE /api/challenges/{challengeId}
```

방장이 자기 방을 없앤다. 참가자 전원에게 예치금을 돌려주고 방을 닫는다.

- 방장이 아니면 **401**
- 이미 시작된 챌린지면 **409** `CHALLENGE_ALREADY_STARTED`

### 1.6 새 에러 코드

| 코드 | 상태 | 언제 |
|---|---|---|
| `DUPLICATE_NICKNAME` | 409 | 가입 시 닉네임이 이미 쓰이는 중 |
| `CHALLENGE_ALREADY_STARTED` | 409 | 시작된 챌린지를 취소하려 할 때 |

---

## 2. 동작이 바뀐 것 (앱 수정 없이 적용됨)

### 2.1 취소한 챌린지에 다시 참가할 수 있다

`(challenge_id, user_id)` 유니크 제약 때문에 취소해도 행이 남는데, 예전에는 그 존재만 보고
`ALREADY_APPLIED` 로 막아서 **한 번 취소하면 같은 방에 영영 못 들어갔다.**
지금은 살아 있는 참가(PENDING/CONFIRMED)일 때만 중복으로 본다.

### 2.2 탈퇴한 이메일로 다시 가입할 수 있다

탈퇴는 레코드를 남기는 soft delete 인데(코인 내역·체크인이 참조한다), 이메일에 유니크 제약이
있어 **같은 이메일로 재가입이 막혔다.** 이제 탈퇴 시점에 이메일을 `withdrawn+{id}@booster.invalid`
로 바꿔 원래 주소를 놓아준다.

### 2.3 방장이 탈퇴하면 모집 중인 자기 방이 해산된다

예전에는 방장이 탈퇴해도 방이 남아, 시작시킬 사람이 없는 방에 참가자 예치금만 묶여 있었다.
이제 전원 환불 + 방 닫기로 정리한다.

**진행 중(ACTIVE) 챌린지는 해산하지 않는다.** 팀이 짜이고 며칠치 체크인이 쌓인 판을 방장 한 명
때문에 무효로 만들면 나머지 참가자가 손해를 본다. 이 경우 방장의 참가만 빠진다.

### 2.4 AI 인증 카테고리가 400 으로 걸린다

`EXERCISE`/`STUDY` 가 아닌 값을 보내면 예전에는 ai-service 가 422 를 주고 백엔드가 그걸
"계약 오류"로 보아 **500** 으로 올렸다. 사용자 입력 때문에 서버 오류가 나는 셈이라,
`AiVerificationClient` 경계에서 **400** 으로 돌려준다. 개인·팀 두 경로가 모두 이 지점을 지난다.

---

## 3. 반경 정책

`GpsPolicy` 에 한 곳으로 모았다. **10m ~ 1000m.**

- 상한이 없던 시절엔 2,000만m 등록이 통과해서 **서울에 등록하고 시드니에서 인증**해도 성공했다
  (실제로 재현 확인함)
- 하한 10m 는 휴대폰 GPS 오차(보통 10~50m)보다 좁으면 제자리에서도 인증이 실패하기 때문

개인 위치 등록·수정, 챌린지 생성, 팀 참가 **세 곳 모두**에 적용된다.
팀 참가는 예전에 범위 검증이 아예 없어서 음수·0 반경이 저장된 뒤 나중에 409 로 터졌다.

---

## 4. 아직 안 한 것 — 프론트 몫

| 항목 | 내용 |
|---|---|
| 캘린더 | 슬라이드로 월 넘기기 + 화살표 |
| 팀 탐색 | 하드코딩 제거 |
| 인증 버튼 | GPS 인증 / 사진 인증 두 개로 분리 |
| 주간목표 | 화면에서 더 눈에 띄게 |
| 온보딩 순서 | 개인목표(운동/공부) → GPS 설정 |
| 워딩 | "주간목표 변경" 이 이제 목표+장소를 함께 다루므로 다른 이름이 필요하다 |

`docs/project-plan.md` 의 파트별 시작점도 이 문서 기준으로 갱신이 필요하다.
