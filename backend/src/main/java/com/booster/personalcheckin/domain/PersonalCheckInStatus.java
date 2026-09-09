package com.booster.personalcheckin.domain;

/**
 * 개인 체크인 상태.
 *
 * <p>"그날 안 했다"는 레코드 부재로 표현한다 — 실패 레코드를 남기지 않는다(미달 판정은 주간 채점이
 * 담당). 남는 상태는 둘뿐이다.
 */
public enum PersonalCheckInStatus {
    /** 인증 확정. */
    SUCCESS,
    /** AI 를 쓰는 목표에서 사진 판정을 기다리는 중. 주간 채점의 성공 집계에는 잡히지 않는다. */
    PENDING
}
