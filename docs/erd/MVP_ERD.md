# Booster MVP ERD

## 1. MVP 기준 테이블 목록
| 테이블명 | 설명 |
|---|---|
| users | 사용자 계정 정보 |
| teams | 팀 정보 |
| team_members | 사용자와 팀의 참여 관계 |
| challenges | 챌린지 기본 정보 |
| challenge_participants | 사용자와 챌린지 참여 관계 |
| challenge_check_ins | 일일 챌린지 수행 기록 |
| verification_submissions | 인증 시도/제출 단위 |
| gps_verification_results | GPS 인증 결과 |
| ai_verification_results | AI 인증 결과 (Phase 2 확장, MVP 구현 보류) |
| verification_decisions | 최종 체크인 성공/실패 판정 |
| ~~verification_logs~~ | (deprecated) 통합형 초기안, 미채택 — `docs/database/BS-27-verification-schema-decision.md` 참조 |
| recovery_missions | 실패 이후 복귀를 위한 미션 정보 |
| leaderboards | 개인/팀 랭킹 집계 정보 |
| notifications | 사용자 알림 정보 |
| user_settings | 사용자별 알림 및 서비스 설정 |
| challenge_rules | 챌린지 수행 규칙 정보 |

## 2. 주요 관계
- users 1:N team_members
- teams 1:N team_members
- teams 1:N challenges
- challenges 1:N challenge_participants
- users 1:N challenge_participants
- users 1:N challenge_check_ins
- challenges 1:N challenge_check_ins
- challenge_check_ins 1:N verification_submissions
- verification_submissions 1:1 gps_verification_results
- verification_submissions 1:1 ai_verification_results (Phase 2 확장)
- verification_submissions 1:1 verification_decisions
- users 1:N recovery_missions
- challenges 1:N recovery_missions
- challenge_check_ins 1:0..1 recovery_missions
- users 1:N notifications
- users 1:1 user_settings
- challenges 1:1 challenge_rules

## 3. MVP ERD 설계 기준

Booster MVP의 ERD는 팀 기반 습관 챌린지 서비스의 핵심 흐름을 구현하기 위한 최소 테이블을 기준으로 설계한다.

MVP의 핵심 흐름은 다음과 같다.

1. 사용자는 팀에 가입하거나 팀을 생성할 수 있다.
2. 팀은 여러 개의 챌린지를 생성할 수 있다.
3. 사용자는 챌린지에 참여하고 매일 체크인을 수행한다.
4. 체크인 과정에서 인증 제출이 생성되고, MVP에서는 GPS 인증 결과를 기준으로 최종 판정이 기록된다. (사진/AI 인증은 Phase 2 확장)
5. 사용자가 정해진 시간 안에 체크인을 완료하지 못하거나 실패한 경우 복귀 미션이 생성될 수 있다.
6. 챌린지 수행 결과는 개인 또는 팀 단위 리더보드로 집계된다.
7. 알림 기능은 체크인 독려, 미수행 안내, 복귀 미션 안내에 사용된다.
8. 사용자 설정은 알림 수신 여부, 알림 시간 등 개인별 서비스 설정을 관리한다.
9. 챌린지 규칙은 인증 방식, 수행 주기, 마감 시간, 복귀 조건 등을 관리한다.

## 4. 테이블별 역할

### users
사용자 계정 정보를 저장하는 테이블이다.  
이메일, 비밀번호, 닉네임, 가입일, 계정 상태 등의 정보를 관리한다.

### teams
팀 정보를 저장하는 테이블이다.  
팀 이름, 팀 설명, 팀 생성자, 생성일 등의 정보를 관리한다.

### team_members
사용자와 팀의 참여 관계를 관리하는 테이블이다.  
하나의 사용자가 여러 팀에 참여할 수 있고, 하나의 팀에 여러 사용자가 참여할 수 있으므로 users와 teams 사이의 다대다 관계를 해소하는 역할을 한다.

### challenges
챌린지 기본 정보를 저장하는 테이블이다.  
챌린지 제목, 설명, 시작일, 종료일, 챌린지 상태, 소속 팀 등의 정보를 관리한다.

### challenge_participants
사용자와 챌린지의 참여 관계를 관리하는 테이블이다.  
하나의 사용자가 여러 챌린지에 참여할 수 있고, 하나의 챌린지에 여러 사용자가 참여할 수 있으므로 users와 challenges 사이의 다대다 관계를 해소하는 역할을 한다.

### challenge_check_ins
사용자의 일일 챌린지 수행 기록을 저장하는 기준 테이블이다.  
특정 참여자가 특정 챌린지에서 특정 날짜에 수행을 성공했는지, 실패했는지 등을 관리한다. A-axis의 개인 체크인과 분리된 팀 챌린지 전용 테이블이다.

### verification_submissions
하나의 체크인에 대한 인증 시도/제출 단위를 저장하는 테이블이다.  
제출 시각, 제출 좌표, 제출 이미지(선택), 시도 회차 등을 기록한다. 하나의 체크인에 여러 제출이 있을 수 있다.

### gps_verification_results
하나의 인증 제출에 대한 GPS 위치 인증 결과를 저장하는 테이블이다.  
목표/제출 좌표, 허용 반경, 산출 거리, 반경 내 포함 여부 등을 기록한다. MVP 인증 판정의 핵심 입력이다.

### ai_verification_results
하나의 인증 제출에 대한 AI(사진/동작) 인증 결과를 저장하는 테이블이다.  
모델명, 탐지 라벨, 신뢰도 점수, 통과 여부 등을 기록한다. **MVP에서는 구현을 보류하며 Phase 2 확장 대상이다.**

### verification_decisions
하나의 인증 제출에 대한 최종 체크인 성공/실패 판정을 저장하는 테이블이다.  
GPS 통과 여부, AI 통과 여부, 최종 통과 여부, 실패 사유 등을 종합한다. **MVP에서는 GPS 결과만으로 최종 판정을 산출한다.**

### ~~verification_logs~~ (deprecated)
GPS/사진/AI/최종 판정을 한 테이블에 통합 저장하던 초기안이다. 책임이 섞여 미채택되었으며, 위 분리형 테이블들로 대체되었다. 사유는 `docs/database/BS-27-verification-schema-decision.md` 참조.

### recovery_missions
사용자가 체크인에 실패했거나 수행 흐름에서 이탈했을 때 다시 복귀할 수 있도록 제공되는 미션 정보를 저장하는 테이블이다.  
복귀 미션 내용, 마감 시간, 수행 상태, 연결된 사용자, 챌린지, 체크인 기록 등을 관리한다.

### leaderboards
챌린지별 개인 또는 팀 랭킹 정보를 저장하거나 조회하기 위한 테이블이다.  
점수, 순위, 성공 횟수, 연속 수행 일수 등의 정보를 관리한다.

### notifications
사용자에게 전달되는 알림 정보를 저장하는 테이블이다.  
체크인 알림, 미수행 알림, 복귀 미션 알림, 팀 관련 알림 등을 관리한다.

### user_settings
사용자별 서비스 설정 정보를 저장하는 테이블이다.  
알림 수신 여부, 알림 시간, 마케팅 수신 여부 등 개인별 설정 값을 관리한다.

### challenge_rules
챌린지 수행 규칙을 저장하는 테이블이다.  
수행 주기, 인증 방식, 체크인 마감 시간, 복귀 미션 허용 여부, 지연 성공 처리 기준 등을 관리한다.

## 5. MVP 기준 테이블 포함 이유

| 테이블명 | 포함 이유 |
|---|---|
| users | 모든 사용자 활동의 기준이 되는 핵심 테이블 |
| teams | 팀 기반 챌린지 기능 구현을 위한 핵심 테이블 |
| team_members | 사용자와 팀의 다대다 관계 관리 |
| challenges | 습관 챌린지 생성 및 운영을 위한 핵심 테이블 |
| challenge_participants | 사용자와 챌린지의 다대다 관계 관리 |
| challenge_check_ins | 일일 수행 여부와 연속 기록 관리를 위한 핵심 테이블 |
| verification_submissions | 인증 시도/제출 단위 기록 |
| gps_verification_results | GPS 인증 결과 저장 (MVP 인증 판정 입력) |
| ai_verification_results | AI 인증 결과 저장 (Phase 2 확장, MVP 구현 보류) |
| verification_decisions | 인증 제출에 대한 최종 성공/실패 판정 |
| recovery_missions | Booster의 차별점인 복귀 중심 구조 구현 |
| leaderboards | 개인/팀 성과 시각화 및 경쟁 구조 구현 |
| notifications | 체크인 독려 및 복귀 미션 안내 |
| user_settings | 사용자별 알림 및 서비스 설정 관리 |
| challenge_rules | 챌린지별 수행 규칙 및 인증 조건 관리 |

## 6. MVP 기준 보류 가능 항목

MVP에서는 핵심 기능 구현을 우선하기 위해 다음 항목은 별도 테이블로 분리하지 않고 추후 확장 대상으로 둔다.

| 항목 | 처리 방향 |
|---|---|
| 실제 결제 및 환급 | MVP에서는 제외하거나 가상 포인트로 대체 |
| 실제 기부 정산 | 추후 확장 기능으로 분리 |
| 상세 AI 모델 학습 이력 | MVP에서는 AI 인증 자체를 보류(Phase 2). 확장 시 ai_verification_results에 결과만 저장 |
| 상세 통계 및 분석 데이터 | challenge_check_ins 기반 조회로 우선 처리 |
| 휴식권 및 면책권 | challenge_rules에 규칙 값으로 우선 관리 후 추후 분리 |
| 친구/팔로우 기능 | MVP 이후 소셜 기능 확장 시 추가 |
| 게시글/댓글 기능 | MVP 이후 커뮤니티 기능 확장 시 추가 |

## 7. ERD 설계 메모

- users와 teams는 team_members를 통해 다대다 관계를 가진다.
- users와 challenges는 challenge_participants를 통해 다대다 관계를 가진다.
- challenge_check_ins는 사용자의 일일 수행 기록을 나타내며, 인증 결과는 verification_submissions → gps_verification_results / ai_verification_results / verification_decisions 로 분리하여 저장한다. 통합형 verification_logs는 deprecated이다.
- recovery_missions는 실패한 체크인과 연결될 수 있으므로 challenge_check_ins와 1:0..1 관계를 가진다.
- leaderboards는 실제 저장 테이블로 둘 수도 있고, challenge_check_ins와 challenge_participants를 기반으로 계산되는 조회용 테이블 또는 뷰로 처리할 수도 있다.
- user_settings는 사용자별 설정을 관리하므로 users와 1:1 관계로 둔다.
- challenge_rules는 챌린지별 수행 조건을 관리하므로 challenges와 1:1 관계로 둔다.