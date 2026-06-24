package com.booster.shared.common;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

/**
 * KST 기준 시계. bs-25 §공통: 모든 날짜 계산은 Asia/Seoul 기준.
 * 테스트에서 고정 Clock으로 대체하여 스트릭/데드라인 로직을 검증한다.
 */
@Configuration
public class ClockConfig {

    public static final ZoneId KST = ZoneId.of("Asia/Seoul");

    @Bean
    public Clock kstClock() {
        return Clock.system(KST);
    }
}
