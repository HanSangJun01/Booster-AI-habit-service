# Booster MVP API SPEC

## 1. API 설계 기준

Booster MVP API는 팀 기반 습관 챌린지 서비스의 핵심 흐름을 기준으로 설계한다.

MVP 핵심 흐름은 다음과 같다.

1. 사용자는 회원가입 및 로그인을 할 수 있다.
2. 사용자는 팀을 생성하거나 기존 팀에 참여할 수 있다.
3. 팀은 챌린지를 생성할 수 있다.
4. 사용자는 챌린지에 참여할 수 있다.
5. 사용자는 매일 챌린지에 대한 체크인을 수행할 수 있다.
6. 체크인 과정에서 MVP 기준 GPS 인증 결과를 기록하며, 사진 및 AI 인증 결과는 Phase 2 확장 대상으로 둔다.
7. 사용자가 체크인에 실패하거나 지연된 경우 복귀 미션을 생성하고 수행할 수 있다.
8. 챌린지 결과는 개인 또는 팀 단위 리더보드로 조회할 수 있다.
9. 사용자는 체크인 알림, 미수행 알림, 복귀 미션 알림을 받을 수 있다.
10. 사용자는 알림 수신 여부와 알림 시간 등 개인 설정을 관리할 수 있다.

## 2. 공통 규칙

### 2.1 Base URL

```text
/api
```

### 2.2 Response 공통 형식

```json
{
  "success": true,
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

### 2.3 Error Response 공통 형식

```json
{
  "success": false,
  "message": "요청 처리 중 오류가 발생했습니다.",
  "errorCode": "ERROR_CODE"
}
```

### 2.4 주요 상태 코드

| HTTP Status | 설명 |
|---|---|
| 200 OK | 조회 또는 수정 성공 |
| 201 Created | 생성 성공 |
| 400 Bad Request | 잘못된 요청 |
| 401 Unauthorized | 인증 실패 |
| 403 Forbidden | 권한 없음 |
| 404 Not Found | 리소스 없음 |
| 409 Conflict | 중복 또는 충돌 |
| 500 Internal Server Error | 서버 내부 오류 |

## 3. API 목록

| 구분 | Method | Endpoint | 설명 |
|---|---|---|---|
| Auth | POST | /api/auth/signup | 회원가입 |
| Auth | POST | /api/auth/login | 로그인 |
| Users | GET | /api/users/{userId} | 사용자 정보 조회 |
| Users | PATCH | /api/users/{userId} | 사용자 정보 수정 |
| Teams | POST | /api/teams | 팀 생성 |
| Teams | GET | /api/teams/{teamId} | 팀 상세 조회 |
| Teams | GET | /api/users/{userId}/teams | 사용자가 참여 중인 팀 목록 조회 |
| Teams | POST | /api/teams/{teamId}/members | 팀 참여 |
| Teams | DELETE | /api/teams/{teamId}/members/{userId} | 팀 탈퇴 |
| Challenges | POST | /api/teams/{teamId}/challenges | 팀 챌린지 생성 |
| Challenges | GET | /api/challenges/{challengeId} | 챌린지 상세 조회 |
| Challenges | GET | /api/teams/{teamId}/challenges | 팀 챌린지 목록 조회 |
| Challenges | POST | /api/challenges/{challengeId}/participants | 챌린지 참여 |
| Challenges | DELETE | /api/challenges/{challengeId}/participants/{userId} | 챌린지 참여 취소 |
| CheckIns | POST | /api/challenges/{challengeId}/check-ins | 일일 체크인 생성 |
| CheckIns | GET | /api/challenges/{challengeId}/check-ins | 챌린지 체크인 목록 조회 |
| CheckIns | GET | /api/users/{userId}/check-ins | 사용자 체크인 목록 조회 |
| Verifications | POST | /api/check-ins/{checkInId}/verification-submissions | 인증 제출 생성 (MVP: GPS 인증) |
| Verifications | GET | /api/check-ins/{checkInId}/verification-submissions | 인증 제출/결과 목록 조회 |
| Verifications | ~~POST/GET~~ | ~~/api/check-ins/{checkInId}/verification-logs~~ | (deprecated) 통합형 초기안, 미채택 — BS-27 참조 |
| Recovery | POST | /api/check-ins/{checkInId}/recovery-missions | 복귀 미션 생성 |
| Recovery | GET | /api/users/{userId}/recovery-missions | 사용자 복귀 미션 목록 조회 |
| Recovery | PATCH | /api/recovery-missions/{recoveryMissionId} | 복귀 미션 수행 결과 수정 |
| Leaderboards | GET | /api/challenges/{challengeId}/leaderboards | 챌린지 리더보드 조회 |
| Notifications | GET | /api/users/{userId}/notifications | 사용자 알림 목록 조회 |
| Notifications | PATCH | /api/notifications/{notificationId}/read | 알림 읽음 처리 |
| Settings | GET | /api/users/{userId}/settings | 사용자 설정 조회 |
| Settings | PATCH | /api/users/{userId}/settings | 사용자 설정 수정 |

## 4. Auth API

## 4.1 회원가입

### POST /api/auth/signup

사용자 계정을 생성한다.

#### Request

```json
{
  "email": "user@example.com",
  "password": "password1234",
  "nickname": "booster_user"
}
```

#### Response

```json
{
  "success": true,
  "message": "회원가입이 완료되었습니다.",
  "data": {
    "userId": 1,
    "email": "user@example.com",
    "nickname": "booster_user",
    "createdAt": "2026-06-03T10:00:00"
  }
}
```

---

## 4.2 로그인

### POST /api/auth/login

사용자 로그인을 처리한다.

#### Request

```json
{
  "email": "user@example.com",
  "password": "password1234"
}
```

#### Response

```json
{
  "success": true,
  "message": "로그인이 완료되었습니다.",
  "data": {
    "userId": 1,
    "email": "user@example.com",
    "nickname": "booster_user",
    "accessToken": "access-token-example"
  }
}
```

## 5. Users API

## 5.1 사용자 정보 조회

### GET /api/users/{userId}

사용자 정보를 조회한다.

#### Response

```json
{
  "success": true,
  "message": "사용자 정보 조회에 성공했습니다.",
  "data": {
    "userId": 1,
    "email": "user@example.com",
    "nickname": "booster_user",
    "profileImageUrl": "https://example.com/profile.png",
    "createdAt": "2026-06-03T10:00:00"
  }
}
```

---

## 5.2 사용자 정보 수정

### PATCH /api/users/{userId}

사용자의 닉네임, 프로필 이미지 등을 수정한다.

#### Request

```json
{
  "nickname": "new_booster_user",
  "profileImageUrl": "https://example.com/new-profile.png"
}
```

#### Response

```json
{
  "success": true,
  "message": "사용자 정보가 수정되었습니다.",
  "data": {
    "userId": 1,
    "nickname": "new_booster_user",
    "profileImageUrl": "https://example.com/new-profile.png",
    "updatedAt": "2026-06-03T11:00:00"
  }
}
```

## 6. Teams API

## 6.1 팀 생성

### POST /api/teams

새로운 팀을 생성한다.

#### Request

```json
{
  "name": "아침 러닝 팀",
  "description": "매일 아침 러닝을 목표로 하는 팀입니다.",
  "ownerId": 1
}
```

#### Response

```json
{
  "success": true,
  "message": "팀이 생성되었습니다.",
  "data": {
    "teamId": 1,
    "name": "아침 러닝 팀",
    "description": "매일 아침 러닝을 목표로 하는 팀입니다.",
    "ownerId": 1,
    "createdAt": "2026-06-03T10:00:00"
  }
}
```

---

## 6.2 팀 상세 조회

### GET /api/teams/{teamId}

팀 상세 정보를 조회한다.

#### Response

```json
{
  "success": true,
  "message": "팀 정보 조회에 성공했습니다.",
  "data": {
    "teamId": 1,
    "name": "아침 러닝 팀",
    "description": "매일 아침 러닝을 목표로 하는 팀입니다.",
    "ownerId": 1,
    "memberCount": 5,
    "createdAt": "2026-06-03T10:00:00"
  }
}
```

---

## 6.3 사용자가 참여 중인 팀 목록 조회

### GET /api/users/{userId}/teams

특정 사용자가 참여 중인 팀 목록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "참여 중인 팀 목록 조회에 성공했습니다.",
  "data": [
    {
      "teamId": 1,
      "name": "아침 러닝 팀",
      "description": "매일 아침 러닝을 목표로 하는 팀입니다.",
      "role": "MEMBER"
    }
  ]
}
```

---

## 6.4 팀 참여

### POST /api/teams/{teamId}/members

사용자가 팀에 참여한다.

#### Request

```json
{
  "userId": 1
}
```

#### Response

```json
{
  "success": true,
  "message": "팀 참여가 완료되었습니다.",
  "data": {
    "teamId": 1,
    "userId": 1,
    "role": "MEMBER",
    "joinedAt": "2026-06-03T10:00:00"
  }
}
```

---

## 6.5 팀 탈퇴

### DELETE /api/teams/{teamId}/members/{userId}

사용자가 팀에서 탈퇴한다.

#### Response

```json
{
  "success": true,
  "message": "팀 탈퇴가 완료되었습니다.",
  "data": null
}
```

## 7. Challenges API

## 7.1 팀 챌린지 생성

### POST /api/teams/{teamId}/challenges

팀에 새로운 챌린지를 생성한다.

#### Request

```json
{
  "title": "30일 아침 러닝 챌린지",
  "description": "매일 아침 30분 이상 러닝하기",
  "startDate": "2026-06-10",
  "endDate": "2026-07-10",
  "verificationType": "GPS_PHOTO",
  "deadlineTime": "23:00",
  "recoveryEnabled": true
}
```

#### Response

```json
{
  "success": true,
  "message": "챌린지가 생성되었습니다.",
  "data": {
    "challengeId": 1,
    "teamId": 1,
    "title": "30일 아침 러닝 챌린지",
    "status": "READY",
    "verificationType": "GPS_PHOTO",
    "createdAt": "2026-06-03T10:00:00"
  }
}
```

---

## 7.2 챌린지 상세 조회

### GET /api/challenges/{challengeId}

챌린지 상세 정보를 조회한다.

#### Response

```json
{
  "success": true,
  "message": "챌린지 상세 조회에 성공했습니다.",
  "data": {
    "challengeId": 1,
    "teamId": 1,
    "title": "30일 아침 러닝 챌린지",
    "description": "매일 아침 30분 이상 러닝하기",
    "startDate": "2026-06-10",
    "endDate": "2026-07-10",
    "status": "ACTIVE",
    "verificationType": "GPS_PHOTO",
    "deadlineTime": "23:00",
    "recoveryEnabled": true
  }
}
```

---

## 7.3 팀 챌린지 목록 조회

### GET /api/teams/{teamId}/challenges

특정 팀에서 진행 중인 챌린지 목록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "팀 챌린지 목록 조회에 성공했습니다.",
  "data": [
    {
      "challengeId": 1,
      "title": "30일 아침 러닝 챌린지",
      "status": "ACTIVE",
      "startDate": "2026-06-10",
      "endDate": "2026-07-10"
    }
  ]
}
```

---

## 7.4 챌린지 참여

### POST /api/challenges/{challengeId}/participants

사용자가 챌린지에 참여한다.

#### Request

```json
{
  "userId": 1
}
```

#### Response

```json
{
  "success": true,
  "message": "챌린지 참여가 완료되었습니다.",
  "data": {
    "challengeId": 1,
    "userId": 1,
    "joinedAt": "2026-06-03T10:00:00",
    "status": "ACTIVE"
  }
}
```

---

## 7.5 챌린지 참여 취소

### DELETE /api/challenges/{challengeId}/participants/{userId}

사용자가 챌린지 참여를 취소한다.

#### Response

```json
{
  "success": true,
  "message": "챌린지 참여가 취소되었습니다.",
  "data": null
}
```

## 8. CheckIns API

## 8.1 일일 체크인 생성

### POST /api/challenges/{challengeId}/check-ins

사용자의 일일 챌린지 수행 기록을 생성한다.

#### Request

```json
{
  "userId": 1,
  "checkInDate": "2026-06-10",
  "status": "SUCCESS"
}
```

#### Response

```json
{
  "success": true,
  "message": "체크인이 생성되었습니다.",
  "data": {
    "checkInId": 1,
    "challengeId": 1,
    "userId": 1,
    "checkInDate": "2026-06-10",
    "status": "SUCCESS",
    "createdAt": "2026-06-10T08:30:00"
  }
}
```

---

## 8.2 챌린지 체크인 목록 조회

### GET /api/challenges/{challengeId}/check-ins

특정 챌린지의 체크인 기록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "챌린지 체크인 목록 조회에 성공했습니다.",
  "data": [
    {
      "checkInId": 1,
      "challengeId": 1,
      "userId": 1,
      "nickname": "booster_user",
      "checkInDate": "2026-06-10",
      "status": "SUCCESS"
    }
  ]
}
```

---

## 8.3 사용자 체크인 목록 조회

### GET /api/users/{userId}/check-ins

특정 사용자의 체크인 기록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "사용자 체크인 목록 조회에 성공했습니다.",
  "data": [
    {
      "checkInId": 1,
      "challengeId": 1,
      "challengeTitle": "30일 아침 러닝 챌린지",
      "checkInDate": "2026-06-10",
      "status": "SUCCESS"
    }
  ]
}
```

## 9. Verifications API

> BS-27 결정에 따라 인증 구조는 분리형(verification_submissions / gps_verification_results / ai_verification_results / verification_decisions)으로 확정되었다.
> MVP는 GPS 인증 중심이며, 최종 판정은 GPS 결과만으로 산출한다. AI 인증(imageUrl, aiResult, confidenceScore)은 Phase 2 확장이다.
> 기존 통합형 `/verification-logs`는 deprecated이다(§9.3).

## 9.1 인증 제출 생성

### POST /api/check-ins/{checkInId}/verification-submissions

체크인에 대한 인증 제출을 생성하고, MVP에서는 GPS 인증 결과를 기준으로 최종 판정을 산출한다.

#### Request (MVP — GPS 중심)

```json
{
  "latitude": 37.5665,
  "longitude": 126.9780
}
```

- `imageUrl` (optional): 사진 인증용. **Phase 2 확장** 입력이며 MVP 판정에는 사용하지 않는다.
- `aiResult`, `confidenceScore`: **MVP 요청 바디에서 제거.** AI 인증 결과는 Phase 2 확장 대상이다.

#### Response

```json
{
  "success": true,
  "message": "인증 제출이 처리되었습니다.",
  "data": {
    "submissionId": 1,
    "checkInId": 1,
    "gpsResult": {
      "distanceMeters": 12,
      "isWithinRadius": true
    },
    "finalPassed": true,
    "failureReason": null,
    "createdAt": "2026-06-10T08:31:00"
  }
}
```

- `gpsResult`: gps_verification_results에 저장된 GPS 인증 결과 (거리·반경 내 포함 여부).
- `finalPassed`, `failureReason`: verification_decisions에 저장된 최종 판정. MVP에서는 GPS 결과만으로 결정된다.

---

## 9.2 인증 제출/결과 조회

### GET /api/check-ins/{checkInId}/verification-submissions

특정 체크인에 연결된 인증 제출과 결과 목록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "인증 제출 목록 조회에 성공했습니다.",
  "data": [
    {
      "submissionId": 1,
      "latitude": 37.5665,
      "longitude": 126.9780,
      "gpsResult": {
        "distanceMeters": 12,
        "isWithinRadius": true
      },
      "finalPassed": true,
      "failureReason": null,
      "createdAt": "2026-06-10T08:31:00"
    }
  ]
}
```

---

## 9.3 (deprecated) 체크인 인증 로그

### ~~POST/GET /api/check-ins/{checkInId}/verification-logs~~

GPS/사진/AI 인증 결과와 최종 판정을 단일 `verification_logs` 테이블에 통합 저장하던 초기안이다. 책임이 섞여 미채택되었으며, §9.1·§9.2의 분리형 엔드포인트로 대체되었다. 사유는 `docs/database/BS-27-verification-schema-decision.md` 참조.

## 10. Recovery Missions API

## 10.1 복귀 미션 생성

### POST /api/check-ins/{checkInId}/recovery-missions

실패 또는 미수행 체크인에 대한 복귀 미션을 생성한다.

#### Request

```json
{
  "userId": 1,
  "challengeId": 1,
  "missionType": "SHORT_ACTION",
  "description": "오늘 10분 러닝 후 사진 인증하기",
  "dueAt": "2026-06-11T12:00:00"
}
```

#### Response

```json
{
  "success": true,
  "message": "복귀 미션이 생성되었습니다.",
  "data": {
    "recoveryMissionId": 1,
    "checkInId": 1,
    "userId": 1,
    "challengeId": 1,
    "missionType": "SHORT_ACTION",
    "description": "오늘 10분 러닝 후 사진 인증하기",
    "status": "PENDING",
    "dueAt": "2026-06-11T12:00:00"
  }
}
```

---

## 10.2 사용자 복귀 미션 목록 조회

### GET /api/users/{userId}/recovery-missions

특정 사용자의 복귀 미션 목록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "복귀 미션 목록 조회에 성공했습니다.",
  "data": [
    {
      "recoveryMissionId": 1,
      "challengeId": 1,
      "challengeTitle": "30일 아침 러닝 챌린지",
      "description": "오늘 10분 러닝 후 사진 인증하기",
      "status": "PENDING",
      "dueAt": "2026-06-11T12:00:00"
    }
  ]
}
```

---

## 10.3 복귀 미션 수행 결과 수정

### PATCH /api/recovery-missions/{recoveryMissionId}

복귀 미션의 수행 결과를 수정한다.

#### Request

```json
{
  "status": "SUCCESS"
}
```

#### Response

```json
{
  "success": true,
  "message": "복귀 미션 상태가 수정되었습니다.",
  "data": {
    "recoveryMissionId": 1,
    "status": "SUCCESS",
    "completedAt": "2026-06-11T10:30:00"
  }
}
```

## 11. Leaderboards API

## 11.1 챌린지 리더보드 조회

### GET /api/challenges/{challengeId}/leaderboards

챌린지의 개인 또는 팀 리더보드를 조회한다.

#### Query Parameter

| 이름 | 타입 | 필수 여부 | 설명 |
|---|---|---|---|
| type | String | N | PERSONAL 또는 TEAM |

#### Request Example

```text
GET /api/challenges/1/leaderboards?type=PERSONAL
```

#### Response

```json
{
  "success": true,
  "message": "리더보드 조회에 성공했습니다.",
  "data": {
    "challengeId": 1,
    "type": "PERSONAL",
    "rankings": [
      {
        "rank": 1,
        "userId": 1,
        "nickname": "booster_user",
        "score": 120,
        "successCount": 10,
        "streakCount": 7
      }
    ]
  }
}
```

## 12. Notifications API

## 12.1 사용자 알림 목록 조회

### GET /api/users/{userId}/notifications

사용자에게 전달된 알림 목록을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "알림 목록 조회에 성공했습니다.",
  "data": [
    {
      "notificationId": 1,
      "type": "CHECK_IN_REMINDER",
      "title": "오늘의 인증 시간이 얼마 남지 않았어요.",
      "message": "23:00 전까지 오늘의 챌린지를 인증해주세요.",
      "isRead": false,
      "createdAt": "2026-06-10T21:00:00"
    }
  ]
}
```

---

## 12.2 알림 읽음 처리

### PATCH /api/notifications/{notificationId}/read

특정 알림을 읽음 처리한다.

#### Response

```json
{
  "success": true,
  "message": "알림이 읽음 처리되었습니다.",
  "data": {
    "notificationId": 1,
    "isRead": true,
    "readAt": "2026-06-10T21:10:00"
  }
}
```

## 13. User Settings API

## 13.1 사용자 설정 조회

### GET /api/users/{userId}/settings

사용자의 알림 및 서비스 설정을 조회한다.

#### Response

```json
{
  "success": true,
  "message": "사용자 설정 조회에 성공했습니다.",
  "data": {
    "userId": 1,
    "notificationEnabled": true,
    "reminderTime": "21:00",
    "recoveryNotificationEnabled": true
  }
}
```

---

## 13.2 사용자 설정 수정

### PATCH /api/users/{userId}/settings

사용자의 알림 및 서비스 설정을 수정한다.

#### Request

```json
{
  "notificationEnabled": true,
  "reminderTime": "21:00",
  "recoveryNotificationEnabled": true
}
```

#### Response

```json
{
  "success": true,
  "message": "사용자 설정이 수정되었습니다.",
  "data": {
    "userId": 1,
    "notificationEnabled": true,
    "reminderTime": "21:00",
    "recoveryNotificationEnabled": true,
    "updatedAt": "2026-06-03T11:00:00"
  }
}
```

## 14. 상태값 정의

## 14.1 challenge_status

| 값 | 설명 |
|---|---|
| READY | 시작 전 |
| ACTIVE | 진행 중 |
| ENDED | 종료 |
| CANCELLED | 취소됨 |

## 14.2 check_in_status

| 값 | 설명 |
|---|---|
| SUCCESS | 정상 수행 |
| FAILED | 실패 또는 미수행 |
| LATE_SUCCESS | 지연 성공 |
| PENDING | 인증 대기 |

## 14.3 verification_type

| 값 | 설명 | 범위 |
|---|---|---|
| GPS | GPS 위치 인증 | MVP |
| PHOTO | 사진 인증 | Phase 2 |
| AI | AI 이미지 인증 | Phase 2 |
| GPS_PHOTO | GPS + 사진 인증 | Phase 2 |
| GPS_PHOTO_AI | GPS + 사진 + AI 인증 | Phase 2 |

> MVP는 GPS 인증만 사용한다. 사진/AI 조합 타입은 Phase 2 확장 대상이다.

## 14.4 인증 결과 / 최종 판정 (역할 분리)

BS-27 분리형 구조에서 "개별 인증 결과"와 "최종 판정"은 서로 다른 테이블·의미를 가진다.

### gps_verification_results (GPS 인증 결과)

GPS 제출 1건에 대한 위치 인증 결과. 거리·반경 기반의 사실 데이터이며, 그 자체로 체크인 성공을 의미하지 않는다.

| 필드 | 설명 |
|---|---|
| distanceMeters | 목표 좌표와 제출 좌표 간 거리(m) |
| isWithinRadius | 허용 반경 내 포함 여부 (true/false) |

### verification_decisions (최종 판정)

인증 제출에 대한 최종 체크인 성공/실패 판정. MVP에서는 GPS 결과만으로 산출한다.

| 값 (finalPassed) | 설명 |
|---|---|
| true | 최종 인증 성공 |
| false | 최종 인증 실패 (failureReason에 사유 기록) |

> AI 통과 여부(`aiResult` 등)는 Phase 2에서 verification_decisions 종합 판정에 추가된다. MVP에서는 미사용/NULL.
> 기존 통합형 `verification_result`(PASS/FAIL/PENDING) 단일 상태값은 deprecated이다.

## 14.5 recovery_status

| 값 | 설명 |
|---|---|
| PENDING | 복귀 미션 대기 |
| SUCCESS | 복귀 미션 성공 |
| FAILED | 복귀 미션 실패 |
| EXPIRED | 복귀 미션 만료 |

## 14.6 team_member_role

| 값 | 설명 |
|---|---|
| OWNER | 팀 생성자 |
| MEMBER | 일반 팀원 |

## 14.7 leaderboard_type

| 값 | 설명 |
|---|---|
| PERSONAL | 개인 리더보드 |
| TEAM | 팀 리더보드 |

## 14.8 notification_type

| 값 | 설명 |
|---|---|
| CHECK_IN_REMINDER | 체크인 독려 알림 |
| CHECK_IN_MISSED | 체크인 미수행 알림 |
| RECOVERY_MISSION | 복귀 미션 알림 |
| TEAM_MESSAGE | 팀 관련 알림 |
| CHALLENGE_NOTICE | 챌린지 공지 알림 |

## 15. MVP 이후 확장 가능 API

MVP 이후 다음 API를 추가할 수 있다.

| 구분 | Endpoint 예시 | 설명 |
|---|---|---|
| Payment | /api/payments | 실제 결제 및 예치금 관리 |
| Donation | /api/donations | 기부 처리 및 기부 내역 관리 |
| Reports | /api/users/{userId}/reports | 사용자 습관 리포트 조회 |
| Statistics | /api/challenges/{challengeId}/statistics | 챌린지 통계 조회 |
| Friends | /api/users/{userId}/friends | 친구 및 팔로우 기능 |
| Posts | /api/challenges/{challengeId}/posts | 챌린지 게시글 기능 |
| Co