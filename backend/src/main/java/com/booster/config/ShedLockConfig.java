package com.booster.config;

import net.javacrumbs.shedlock.core.LockProvider;
import net.javacrumbs.shedlock.provider.jdbctemplate.JdbcTemplateLockProvider;
import net.javacrumbs.shedlock.spring.annotation.EnableSchedulerLock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;

/**
 * [P1 멀티서버] 분산 스케줄러 락(ShedLock) 설정.
 *
 * <p>{@code @Scheduled}는 인스턴스마다 독립 타이머로 실행된다 → N대면 정산 스케줄러가 N번 돌아
 * 코인 이중 지급이 발생한다. ShedLock은 공유 DB의 {@code shedlock} 테이블(V10) 한 행을 락으로
 * 삼아 <b>동시에 한 인스턴스만</b> {@code @SchedulerLock} 메서드 본문을 실행하도록 직렬화한다.
 *
 * <p>{@code usingDbTime()}: 락 만료 판단을 앱 서버 시계가 아닌 <b>DB 시계</b> 기준으로 수행해
 * 인스턴스 간 시계 편차(clock skew)로 락이 조기 만료/이중 획득되는 문제를 없앤다.
 *
 * <p>{@code @EnableScheduling}은 {@link com.booster.BoosterApplication}에 이미 있으므로 여기서
 * 중복 선언하지 않는다. {@code defaultLockAtMostFor}는 락 보유 인스턴스가 죽어도 다른 인스턴스가
 * 최대 이 시간 뒤에는 락을 회수할 수 있게 하는 안전 상한이다.
 */
@Configuration
@EnableSchedulerLock(defaultLockAtMostFor = "PT10M")
public class ShedLockConfig {

    @Bean
    public LockProvider lockProvider(DataSource dataSource) {
        return new JdbcTemplateLockProvider(
                JdbcTemplateLockProvider.Configuration.builder()
                        .withJdbcTemplate(new JdbcTemplate(dataSource))
                        .usingDbTime()
                        .build()
        );
    }
}
