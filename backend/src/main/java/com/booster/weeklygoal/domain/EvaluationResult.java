package com.booster.weeklygoal.domain;

/** 주간 채점 결과. */
public enum EvaluationResult {
    /** 목표 달성. 스트릭 유지. */
    ACHIEVED,
    /** 미달이지만 구제권을 소모해 스트릭을 지켰다. */
    RESCUED,
    /**
     * 미달 + 구제권 없음 → <b>아직 확정되지 않은 상태</b>.
     *
     * <p>스트릭과 코인은 그대로 두고 기한({@code rescueDeadline})까지 구매 기회를 준다.
     * 기한 내 사후 구매하면 {@link #RESCUED}, 기한이 지나면 {@link #FAILED} 로 확정된다.
     * 예고 없이 스트릭이 0이 되는 것을 막기 위한 유예다.
     */
    PENDING_RESCUE,
    /** 미달 확정. 스트릭 초기화 + 코인 차감. */
    FAILED
}
