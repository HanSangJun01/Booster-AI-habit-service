package com.booster.personalcheckin.domain;

/**
 * 개인 체크인 상태.
 *
 * <p>[주간 목표 모델] 이 테이블에는 성공한 인증만 기록한다. "그날 안 했다"는 레코드 부재로
 * 표현하며 별도 상태를 만들지 않는다(미달 판정은 주간 채점이 담당). 과거 모델의
 * {@code RECOVERY_PENDING}/{@code FAILED} 는 복귀 미션 전용 상태였으므로 함께 제거했다.
 */
public enum PersonalCheckInStatus {
    SUCCESS
}
