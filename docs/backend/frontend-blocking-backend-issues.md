# 프론트엔드가 막히는 백엔드 이슈 목록

> 대상: `integration/a-b-axis` 브랜치 백엔드
> 작성 근거: Flutter 앱(`feature/BS-38-flutter-app`) 실기기 연동 테스트 중 발견
> 확인 방법: 백엔드 소스 직접 대조 (코드 수정 없음, 읽기만 수행)
> 작성일: 2026-08-04
> 상태: 백엔드 팀 확인 요청

---

## 요약

앱에서 우회할 수 없거나, 우회하면 오히려 나빠지는 것들만 모았다. 각 항목에
**앱에서 처리하면 안 되는 이유**를 함께 적었다.

| # | 이슈 | 심각도 | 증상 |
|---|---|---|---|
| 1 | 팀 편성 조건이 10명 고정 | **차단** | 정원 4·6·8 챌린지는 영원히 시작되지 않음 |
| 2 | 챌린지 생성 시 방장이 참가자로 등록되지 않음 | **차단** | 방장이 자기 챌린지에서 인증 불가 |
| 3 | 참가자 목록 조회 API 없음 | 높음 | 방장이 신청자를 볼 수 없어 승인 기능이 사실상 사용 불가 |
| 4 | "내가 참여 중인 챌린지" API 없음 | 높음 | 앱 재시작 시 참여 중인 챌린지를 잃어버림 |
| 5 | 공개 챌린지 목록에 참여 여부 표시 없음 | 중간 | 이미 참가한 챌린지가 계속 노출되고 참가 시 409 |
| 6 | 인증 반경 상한 없음 | 중간 | 500m 등 무의미한 반경 등록 가능 |
| 7 | A축/B축 응답 형태 불일치 | 낮음 | 클라이언트가 두 형태를 모두 처리해야 함 |
| 8 | 스펙에 있으나 미구현된 엔드포인트 | 낮음 | 인증 결과 상세 조회 불가 |

---

## 1. 팀 편성 조건이 10명 고정 — **차단**

**증상**: 정원을 4·6·8명으로 만든 챌린지는 정원을 전부 채워도 팀이 편성되지
않는다. 챌린지가 `READY`에 머물고, 팀 체크인은 `ACTIVE`에서만 허용되므로
**해당 챌린지에서는 아무도 인증할 수 없다.**

**근거**:

```java
// team/service/TeamFormationService.java:23,45
private static final int TEAM_SIZE = 5;
...
if (confirmed.size() < TEAM_SIZE * 2) {   // 10명 미만이면 편성 안 함
    return;
}
```

```java
// challengecheckin/service/ChallengeCheckInService.java:65
if (challenge.getStatus() != ChallengeStatus.ACTIVE) {
    throw new IllegalStateException("Check-in is only allowed when challenge is ACTIVE");
}
```

한편 챌린지 생성 검증은 `maxParticipants` 2~10을 허용하고, 앱의 정원 선택지는
`[4, 6, 8, 10]`이다. 즉 **정원 10명 + 10명 전원 참가**인 경우에만 정상 동작한다.

**요청**: 다음 중 하나로 정해달라.
- (a) 팀 크기를 `maxParticipants / 2`로 계산 (정원 4 → 2 vs 2)
- (b) 정원을 10명 고정으로 제한하고 검증도 `@Min(10)`으로 변경
- (c) 정원 미달이어도 시작할 수 있는 별도 조건(방장 수동 시작 등) 추가

(a)를 권장한다. 앱의 정원 선택지를 그대로 살릴 수 있다. 홀수 정원을 허용할지도
함께 정해야 한다(현재 로직은 `i < TEAM_SIZE`로 잘라 A팀에 몰릴 수 있다).

**앱에서 못 하는 이유**: 팀 편성과 상태 전이는 전적으로 서버 로직이다. 앱은
정원 선택지를 10으로 좁히는 것 말고 할 수 있는 게 없고, 그러면 기획된 정원
옵션이 사라진다.

---

## 2. 챌린지 생성 시 방장이 참가자로 등록되지 않음 — **차단**

**증상**: 챌린지를 만들어도 방장은 참가자가 아니다. 인증도 못 하고, 팀 편성
인원에도 포함되지 않으며, 예치금도 내지 않는다. 방장이 참가자가 되는 유일한
경로가 **"공개 챌린지 탐색에서 자기 챌린지를 찾아 참가 신청"** 이다.

이 문제는 이슈 1과 겹쳐서 더 나빠진다. 방장이 인원수에 안 잡히므로 팀 편성에
필요한 10명을 채우기가 더 어렵다.

**근거**:

```java
// challenge/service/ChallengeService.java:42-52
Challenge saved = challengeRepository.save(challenge);   // 참가자 생성 없음
return ChallengeResponse.from(saved);
```

**요청**: `POST /api/challenges` 트랜잭션 안에서 방장을 `CONFIRMED` 참가자로
등록하고 예치금을 차감해달라.

**같이 정해야 할 것**: 참가에는 GPS 기준 위치가 필요하다
(`ParticipationRequest`: `gpsLat`, `gpsLng`, `gpsRadiusMeters`). 생성 요청에
이 필드를 추가할지, 서버가 방장의 등록된 개인 인증 위치
(`GET /api/users/me/location`)를 재사용할지 결정이 필요하다.

**앱에서 처리하면 안 되는 이유**: 원자성. 앱이 "생성 → 참가"를 두 번 호출하면
중간에 실패할 때 **참가자가 없는 빈 챌린지**가 서버에 남는다(챌린지 삭제 API도
없어 정리할 수 없다). 또 나중에 웹 클라이언트가 붙으면 같은 버그가 재발한다.
예치금 차감도 생성과 같은 트랜잭션에 묶여야 정합성이 유지된다.

---

## 3. 참가자 목록 조회 API 없음

**증상**: 방장이 누가 신청했는지 볼 수 없다. `approvalType=LEADER`(방장 승인)
챌린지에서 승인 API는 `participantId`를 요구하는데, 그 id를 얻을 방법이 없어
**승인 기능을 사실상 쓸 수 없다.**

**근거**: `ParticipantController`에는 신청/취소/승인만 있고 조회가 없다.

```
POST   /api/challenges/{challengeId}/participants
DELETE /api/challenges/{challengeId}/participants/{targetUserId}
POST   /api/challenges/{challengeId}/participants/{participantId}/approve
```

**요청**: `GET /api/challenges/{challengeId}/participants` 추가
(상태별 필터 지원 권장 — 방장 화면은 `PENDING`만 필요).

**앱에서 못 하는 이유**: 데이터 자체가 내려오지 않는다.

---

## 4. "내가 참여 중인 챌린지" API 없음

**증상**: 앱을 재시작하면 참여 중인 챌린지를 잃어버린다. 초대 코드나 탐색으로
다시 찾아 들어가야 한다. `GET /api/challenges`는 공개 챌린지 **검색**이라
내 참여 여부와 무관하다.

**요청**: `GET /api/users/me/challenges` 추가.
리포지토리에 `findByUserId`가 이미 있어(`ChallengeParticipantRepository.java:20`)
노출만 하면 된다.

**앱에서 못 하는 이유**: 현재 앱은 이번 세션에 만들거나 참가한 챌린지 **하나만**
메모리에 들고 있다. 영속화하더라도 서버에서 취소·종료된 챌린지를 알 수 없어
잘못된 상태를 보여주게 된다.

---

## 5. 공개 챌린지 목록에 참여 여부 표시 없음

**증상**: 이미 참가한 챌린지가 탐색 목록에 계속 노출된다. 참가를 누르면 409가
난다. 자기가 만든 챌린지도 목록에 그대로 보인다.

**근거**: 중복 참가 자체는 서버가 막고 있어 **데이터 정합성 문제는 없다**.

```java
// participant/service/ParticipationService.java:46-47
if (participantRepository.findByChallengeIdAndUserId(challengeId, userId).isPresent()) {
    throw new IllegalStateException("Already applied to this challenge");
}
```

**요청**: `GET /api/challenges` 응답 항목에 `joined`(또는 `participating`) 플래그
추가를 권장한다. 목록에서 아예 제외하는 것보다 낫다 — "참여 중"으로 표시할 수
있고, 페이징 개수도 정확하다.

**앱에서 처리하면 안 되는 이유**: 두 가지다.
1. **참여 여부를 알 수 없다.** `createdBy`로 내가 만든 것만 구분되고, 남이 만든
   챌린지에 참가한 건 서버가 알려주지 않으면 판정 불가다.
2. **페이징이 깨진다.** 서버가 20개를 주고 앱이 3개를 숨기면 그 페이지는 17개가
   되어 "더 보기" 경계 판정이 어긋난다.

---

## 6. 인증 반경 상한 없음

**증상**: 반경을 500m, 5000m 등으로 등록할 수 있다. 반경이 넓으면 "그 장소에
있었다"는 인증의 의미가 사라진다.

**근거**:

```java
// LocationRequest
@Positive(message = "반경은 0보다 커야 합니다.")
Integer radiusMeters,
```

양수 검증만 있다.

**요청**: 상한 추가(`@Max`). 앱은 현재 선택지를 `20 / 30 / 50m`로 제한했고
기본값은 50m다. 하한 20m는 휴대폰 GPS 오차가 통상 5~20m라 그보다 좁히면
제자리에 있어도 인증이 실패하기 때문이다. 서버 상한도 **50m**를 제안한다.

**앱만으로 부족한 이유**: 앱에서 막아도 API를 직접 호출하면 우회된다. 기존에
100m·500m로 저장된 데이터가 있다면 마이그레이션 정책도 정해야 한다.

---

## 7. A축/B축 응답 형태 불일치

**증상**: 같은 API 안에서 성공 응답 모양이 두 가지다.

| 계열 | 형태 |
|---|---|
| B축 (Challenge/Participant/CheckIn/Team/Settlement/Social) | `{"success": true, "message": ..., "data": ...}` |
| A축 (Auth/User/PersonalCheckIn/PersonalLocation/Recovery/Dashboard) | DTO 그대로 (`{"userId": 1, ...}`) |

에러는 양쪽 모두 `{"success": false, "message": ..., "errorCode": ...}`로 통일돼
있어, **에러만 보면 구분이 안 된다.**

앱은 현재 두 형태를 모두 받아내고 있어(`api_client.dart`) 당장 막히지는 않는다.
다만 새 엔드포인트가 추가될 때마다 어느 쪽인지 확인해야 하는 부담이 있다.

**요청**: 신규 엔드포인트는 한쪽으로 통일해달라. 기존 것의 변경은 앱 수정이
필요하므로 일정 조율이 필요하다.

**부가 사항**: `GET /api/challenges`가 Spring `Page`를 그대로 노출해서 목록이
`data.content`에 들어 있다. 페이지 구현이 바뀌면 계약이 함께 바뀌므로 응답
DTO로 감싸는 것을 권한다.

---

## 8. 스펙에 있으나 미구현된 엔드포인트

`MVP_API_SPEC.md §9.2`의 `GET /api/check-ins/{checkInId}/verification-submissions`
(인증 결과 조회)에 대응하는 컨트롤러가 없다. 앱도 해당 기능을 구현하지 않았다.

**요청**: 구현 예정인지, 스펙에서 제외할 것인지 확정해달라. 스펙 문서와 실제
구현이 어긋난 채로 남으면 다음 작업자가 같은 혼란을 겪는다.

---

## 참고: 백엔드에 있으나 앱이 아직 안 쓰는 것

백엔드 이슈는 아니지만, 연동 범위 파악을 위해 함께 적는다.

| 엔드포인트 | 앱 사용 여부 |
|---|---|
| `GET/POST/DELETE /api/teams/{teamId}/chat` | 미사용 (팀 채팅 화면 없음) |
| `POST /api/challenges/{challengeId}/cheers` | 미사용 (응원 기능 없음) |
| `GET /api/challenges/{challengeId}/leaderboards` | 서비스 계층만 있고 화면 미연결 |

---

## 확인된 정상 동작

문제로 오해하기 쉬운 것들이라 함께 기록한다.

- **중복 참가 차단** — `ParticipationService.java:46`에서 409로 거부된다.
- **만료 토큰 처리** — `RestAuthenticationEntryPoint`가 401 +
  `errorCode: "UNAUTHORIZED"`로 응답한다. 403이 아니다.
- **로그인 실패** — `/api/auth/**`는 `permitAll`이라 엔트리포인트를 타지 않고,
  `BusinessException.unauthorized("INVALID_CREDENTIALS", ...)`가 401로 나간다.
  앱은 이 경로의 401을 "토큰 만료"로 오인하지 않도록 `/auth` 접두사를 제외 처리했다.
- **B축 권한 오류** — `UnauthorizedException`은 403 + `errorCode: "FORBIDDEN"`으로
  매핑된다(`GlobalExceptionHandler.java:44`). 이름과 달리 401이 아니므로 앱은
  이것을 세션 만료로 처리하지 않는다. 의도된 동작인지만 확인 부탁한다.
