package com.booster.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.time.LocalDate;

/**
 * 테스트에서 production kstClock 대신 가변 시계를 주입한다(@Primary).
 * 기본 날짜는 실제 현재보다 충분히 미래로 두어, @CreationTimestamp(joinedAt)가
 * 항상 "어제"보다 과거가 되도록 한다(스케줄러 대상 포함 보장).
 */
@TestConfiguration
public class TestClockConfig {

    @Bean
    @Primary
    public MutableClock clock() {
        return MutableClock.at(LocalDate.of(2035, 6, 11)); // 충분히 미래의 날짜
    }
}
