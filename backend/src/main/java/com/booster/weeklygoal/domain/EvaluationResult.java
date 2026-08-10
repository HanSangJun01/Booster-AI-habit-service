package com.booster.weeklygoal.domain;

/** 주간 채점 결과. */
public enum EvaluationResult {
    /** 목표 달성. 스트릭 유지 + 마일스톤 보상 심사 대상. */
    ACHIEVED,
    /** 미달이지만 구제권을 소모해 스트릭을 지켰다. 보상 심사에서는 제외된다. */
    RESCUED,
    /** 미달 + 구제권 없음. 스트릭 초기화 + 코인 차감. */
    FAILED
}
