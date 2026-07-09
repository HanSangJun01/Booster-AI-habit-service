package com.booster.concurrency;

import com.booster.auth.dto.SignupRequest;
import com.booster.auth.service.AuthService;
import com.booster.coin.domain.CoinTransaction;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.repository.CoinTransactionRepository;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personalcheckin.service.PersonalCheckInService;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.personallocation.service.PersonalLocationService;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.recovery.service.RecoveryService;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.repository.UserRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.Pageable;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * [BS-30] A축 동시성/트랜잭션 레이스 버그를 "실패하는 통합 테스트(RED)"로 고정하기 위한 베이스.
 *
 * <p>핵심 설계 결정:
 * <ul>
 *   <li><b>진짜 PostgreSQL(Testcontainers)</b>: H2(profile "test")는 비관락/락 의미가 달라
 *       동시성 버그를 재현할 수 없다. 프로덕션과 동일한 PG + Flyway(V6~V8) 스키마를 사용한다.</li>
 *   <li><b>@Transactional 절대 금지</b>: 테스트 메서드가 트랜잭션이면 모든 작업이 한 트랜잭션으로
 *       묶여 "동시 커밋"이 사라진다. 각 서비스 호출이 자기 트랜잭션 경계에서 커밋되도록
 *       테스트는 비트랜잭셔널로 둔다.</li>
 *   <li><b>싱글톤 컨테이너</b>: static 블록에서 1회 기동(JVM 종료 시 Ryuk가 정리). 모든 동시성
 *       테스트 클래스가 동일 컨테이너를 공유해 기동 시간을 줄인다.</li>
 * </ul>
 */
@SpringBootTest
@ActiveProfiles("ct")
public abstract class ConcurrencyTestBase {

    /** 모든 동시성 테스트가 공유하는 PostgreSQL 컨테이너(싱글톤). */
    protected static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine");

    static {
        POSTGRES.start(); // JVM 생애 1회. stop()을 호출하지 않아도 Ryuk 사이드카가 정리한다.
    }

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        registry.add("spring.flyway.enabled", () -> "true");
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "none");
    }

    @Autowired protected AuthService authService;
    @Autowired protected PersonalLocationService personalLocationService;
    @Autowired protected PersonalCheckInService personalCheckInService;
    @Autowired protected RecoveryService recoveryService;
    @Autowired protected CoinService coinService;

    @Autowired protected UserRepository userRepository;
    @Autowired protected StreakRepository streakRepository;
    @Autowired protected PersonalCheckInRepository personalCheckInRepository;
    @Autowired protected RecoveryMissionRepository recoveryMissionRepository;
    @Autowired protected CoinTransactionRepository coinTransactionRepository;
    @Autowired protected PersonalLocationRepository personalLocationRepository;

    @Autowired protected PlatformTransactionManager txManager;
    @PersistenceContext protected EntityManager em;

    /** 테스트 간 이메일/유저 충돌 방지를 위한 시퀀스. */
    protected static final AtomicInteger SEQ = new AtomicInteger();

    /** 등록 위치와 정확히 같은 좌표(거리 0m → 반경 내). */
    protected static final double LAT = 37.0;
    protected static final double LNG = 127.0;

    /** 가입(보너스 +500) + 개인 위치 등록까지 마친 신규 유저 id 반환. */
    protected Long newUserWithLocation(String prefix) {
        String email = prefix + SEQ.incrementAndGet() + "-" + System.nanoTime() + "@ct.test";
        Long userId = authService.signup(new SignupRequest(email, "password1234", "u")).userId();
        personalLocationService.register(userId, new LocationRequest(LAT, LNG, 100, "home"));
        return userId;
    }

    /** 트랜잭션 안에서 임의 작업 수행(테스트 셋업용 native UPDATE 등). */
    protected void inTransaction(Runnable work) {
        new TransactionTemplate(txManager).executeWithoutResult(status -> work.run());
    }

    /**
     * 주어진 작업들을 각자 별도 스레드에서 <b>동시에</b> 실행한다.
     * 모든 스레드가 준비될 때까지 대기(startLatch)했다가 일제히 출발 → 트랜잭션 겹침 최대화.
     *
     * @return 각 작업에서 던져진 예외 목록(성공한 작업은 포함되지 않음).
     */
    protected List<Throwable> runConcurrently(List<Runnable> tasks) throws InterruptedException {
        int n = tasks.size();
        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch ready = new CountDownLatch(n);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(n);
        List<Throwable> errors = Collections.synchronizedList(new ArrayList<>());
        try {
            for (Runnable task : tasks) {
                pool.submit(() -> {
                    ready.countDown();
                    try {
                        start.await();
                        task.run();
                    } catch (Throwable t) {
                        errors.add(t);
                    } finally {
                        done.countDown();
                    }
                });
            }
            ready.await(10, TimeUnit.SECONDS); // 모든 스레드 준비 대기
            start.countDown();                 // 일제히 출발
            done.await(60, TimeUnit.SECONDS);  // 종료 대기
        } finally {
            pool.shutdownNow();
        }
        return errors;
    }

    // ---- 검증 도우미 ---------------------------------------------------------

    /** 코인 단일 진실 원천 불변식 좌변: SUM(coin_transactions.amount). */
    protected long ledgerSum(Long userId) {
        return coinTransactionRepository
                .findByUserIdOrderByCreatedAtDescIdDesc(userId, Pageable.unpaged())
                .getContent().stream()
                .mapToLong(CoinTransaction::getAmount)
                .sum();
    }

    /** 특정 사유의 코인 거래 행 수. */
    protected long countTxOfType(Long userId, CoinTransactionReason type) {
        return coinTransactionRepository
                .findByUserIdOrderByCreatedAtDescIdDesc(userId, Pageable.unpaged())
                .getContent().stream()
                .filter(t -> t.getType() == type)
                .count();
    }

    /** 예외 원인 사슬에서 첫 번째 비-wrapper 원인을 찾는다(필요 시). */
    protected Throwable rootBusinessCause(Throwable t) {
        Throwable cur = t;
        while (cur != null) {
            if (cur instanceof com.booster.shared.common.BusinessException) {
                return cur;
            }
            cur = cur.getCause();
        }
        return t;
    }
}
