package com.booster.concurrency;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;

/**
 * [C6 전용] now == deadline 경계를 강제하기 위한 고정 시계.
 * performRecovery 의 {@code now.isAfter(deadline)}(strict)와
 * expireOverdueMissions 의 {@code deadlineAt <= now}(inclusive)가 같은 시각에서 엇갈리는지
 * 검증하려면, 미션 deadline 을 이 고정 instant 와 정확히 동일하게 둬야 한다.
 */
@TestConfiguration
public class FixedClockConfig {

    public static final ZoneId KST = ZoneId.of("Asia/Seoul");

    /** 초 단위로 떨어지는 시각(나노초 0) → DB timestamptz 와 정확히 일치. */
    public static final Instant FIXED_INSTANT =
            LocalDate.of(2035, 6, 11).atTime(LocalTime.of(10, 0, 0))
                    .atZone(KST).toInstant();

    @Bean
    @Primary
    public Clock clock() {
        return Clock.fixed(FIXED_INSTANT, KST);
    }
}
