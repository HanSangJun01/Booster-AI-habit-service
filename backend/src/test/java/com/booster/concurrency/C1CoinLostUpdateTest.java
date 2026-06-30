package com.booster.concurrency;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.support.MutableClock;
import com.booster.support.TestClockConfig;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C1] 코인 lost update — User 전체컬럼 UPDATE가 코인 락을 무력화.
 *
 * <p>{@code PersonalCheckInService.checkIn} 은 보상 미해당(non-reward) 라운드에서 User 를
 * <b>락 없이</b> {@code findById} 후 {@code increaseAttendance()} 로 더럽힌다. User 엔티티에는
 * {@code @Version}/{@code @DynamicUpdate} 가 없어 flush 시 <b>coin_balance 컬럼까지</b> checkIn 이
 * 읽었던 옛 값으로 덮어쓴다. 그 사이 {@code CoinService.charge} 가 비관락으로 코인을 차감해도
 * checkIn 의 stale write 가 차감을 통째로 날린다(lost update).
 *
 * <p>검증은 프로젝트 자체 불변식(bs-25 Principle 2): {@code User.coin_balance == SUM(coin_transactions.amount)}.
 * lost update 가 한 번이라도 발생하면 balance 가 원장 합보다 커져 불변식이 깨진다 → RED.
 *
 * <p>비결정적일 수 있어 날짜를 옮겨가며 다수 라운드를 돌린다(각 라운드: 비-reward checkIn 1건 +
 * 동시 charge 2건). 보상 라운드(스트릭 7의 배수)에서는 grant 가 락을 잡아 안전하므로, 나머지
 * 라운드에서만 취약하다. 환경에 따라 재현이 불안정하면 보고서에 명시한다.
 */
@Import(TestClockConfig.class)
class C1CoinLostUpdateTest extends ConcurrencyTestBase {

    @Autowired MutableClock clock;

    @Test
    @DisplayName("코인 단일 진실 원천: 동시 checkIn(무락 User 갱신) + charge 에서도 balance == SUM(거래)")
    void coinBalanceMustEqualLedgerSum_underConcurrentCheckInAndCharge() throws Exception {
        Long userId = newUserWithLocation("c1-");
        LocalDate start = LocalDate.of(2035, 6, 11);

        int rounds = 40;
        for (int d = 0; d < rounds; d++) {
            clock.setDate(start.plusDays(d)); // 메인 스레드에서만 시계 이동(동시 구간 밖)

            List<Runnable> tasks = new ArrayList<>();
            // T1: 그 날의 정상 인증(대부분 비-reward → User 무락 전체갱신)
            tasks.add(() -> personalCheckInService.checkIn(userId, LAT, LNG));
            // T2,T3: 동시 코인 차감(비관락). 소액(1)이라 잔액은 충분히 유지된다.
            tasks.add(() -> coinService.charge(userId, 1, CoinTransactionReason.RECOVERY_SUCCESS, null));
            tasks.add(() -> coinService.charge(userId, 1, CoinTransactionReason.RECOVERY_SUCCESS, null));

            runConcurrently(tasks); // 예외(거의 없음)는 무시 — 최종 상태로만 판정
        }

        long balance = userRepository.findById(userId).orElseThrow().getCoinBalance();
        long ledger = ledgerSum(userId);

        assertThat(balance)
                .as("코인 단일 진실 원천 불변식: User.coin_balance(%d) 는 SUM(coin_transactions.amount)(%d) 와 "
                        + "항상 같아야 한다. 차이가 있으면 무락 User 전체갱신이 charge 를 덮어쓴 lost update.",
                        balance, ledger)
                .isEqualTo(ledger);
    }
}
