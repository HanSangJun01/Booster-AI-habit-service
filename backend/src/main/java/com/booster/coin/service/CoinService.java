package com.booster.coin.service;

import com.booster.coin.domain.CoinTransaction;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.repository.CoinTransactionRepository;
import com.booster.shared.common.BusinessException;
import com.booster.shared.common.InsufficientCoinException;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 코인 변동의 단일 진입점. 모든 변동은 CoinTransaction으로 기록되며 User.coinBalance와 동기화된다.
 * (bs-25 Principle 2 — 단일 진실 원천)
 */
@Service
@RequiredArgsConstructor
public class CoinService {

    private final UserRepository userRepository;
    private final CoinTransactionRepository coinTransactionRepository;

    /** 코인 지급(+). 지급 후 잔액 반환. */
    @Transactional
    public long grant(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        if (amount < 0) {
            throw new IllegalArgumentException("grant amount must be >= 0: " + amount);
        }
        User user = lockUser(userId);
        user.addCoins(amount);
        coinTransactionRepository.save(
                CoinTransaction.of(userId, reason, amount, user.getCoinBalance(), referenceId));
        return user.getCoinBalance();
    }

    /**
     * 코인 차감(-). 잔액보다 큰 차감 요청은 잔액까지만 차감(effective amount 기록, 잔액 음수 방지).
     * @return 실제 차감된 금액(양수)
     */
    @Transactional
    public long charge(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        if (amount < 0) {
            throw new IllegalArgumentException("charge amount must be >= 0: " + amount);
        }
        User user = lockUser(userId);
        long effective = Math.min(amount, user.getCoinBalance());
        user.addCoins(-effective);
        coinTransactionRepository.save(
                CoinTransaction.of(userId, reason, -effective, user.getCoinBalance(), referenceId));
        return effective;
    }

    /**
     * 엄격 차감(-). 잔액 부족 시 {@link InsufficientCoinException}을 던진다(클램핑 안 함).
     *
     * <p>[BS-A/B 통합] 챌린지 참가 예치금처럼 "부족하면 거절"이 필요한 경로용. 잔액검사와 차감을
     * {@code lockUser} 행 락 안에서 한 트랜잭션으로 수행해, 같은 유저가 서로 다른 두 챌린지에
     * 동시 참여할 때 각각 잔액을 통과시키고 이중 차감(클램핑)돼 장부상 풀 &gt; 실제 징수로 벌어지던
     * TOCTOU를 막는다. (기존 charge는 클램핑이라 조용히 잔액까지만 깎였다.)
     */
    @Transactional
    public void chargeStrict(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        if (amount < 0) {
            throw new IllegalArgumentException("charge amount must be >= 0: " + amount);
        }
        User user = lockUser(userId);
        if (user.getCoinBalance() < amount) {
            throw new InsufficientCoinException(amount, user.getCoinBalance());
        }
        user.addCoins(-amount);
        coinTransactionRepository.save(
                CoinTransaction.of(userId, reason, -amount, user.getCoinBalance(), referenceId));
    }

    @Transactional(readOnly = true)
    public long getBalance(Long userId) {
        return userRepository.findById(userId)
                .map(User::getCoinBalance)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
    }

    private User lockUser(Long userId) {
        return userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
    }
}
