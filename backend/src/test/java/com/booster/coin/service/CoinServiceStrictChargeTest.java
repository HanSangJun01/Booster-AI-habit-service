package com.booster.coin.service;

import com.booster.coin.domain.CoinTransaction;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.repository.CoinTransactionRepository;
import com.booster.shared.common.InsufficientCoinException;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * [BS-A/B 통합] 예치금 차감 TOCTOU 수정 회귀 테스트.
 * chargeStrict는 잔액 부족 시 클램핑하지 않고 InsufficientCoinException을 던져야 하며,
 * 잔액검사와 차감이 lockUser(행 락) 안에서 원자적으로 일어나야 한다.
 */
@ExtendWith(MockitoExtension.class)
class CoinServiceStrictChargeTest {

    @Mock private UserRepository userRepository;
    @Mock private CoinTransactionRepository coinTransactionRepository;

    @InjectMocks
    private CoinService coinService;

    private User userWithBalance(long balance) {
        User u = User.create("a@b.test", "hash", "nick");
        u.addCoins(balance);
        return u;
    }

    @Test
    void chargeStrict_whenEnough_deductsExactAmount_underLock() {
        User user = userWithBalance(100);
        when(userRepository.findByIdForUpdate(1L)).thenReturn(Optional.of(user));

        coinService.chargeStrict(1L, 30, CoinTransactionReason.CHALLENGE_DEPOSIT, 42L);

        assertEquals(70, user.getCoinBalance());       // 정확히 30 차감(클램핑 아님)
        verify(userRepository).findByIdForUpdate(1L);   // 락 경로로 조회
        verify(coinTransactionRepository).save(any(CoinTransaction.class));
    }

    @Test
    void chargeStrict_whenInsufficient_throwsAndDoesNotDeduct() {
        User user = userWithBalance(100);
        when(userRepository.findByIdForUpdate(1L)).thenReturn(Optional.of(user));

        assertThrows(InsufficientCoinException.class, () ->
                coinService.chargeStrict(1L, 200, CoinTransactionReason.CHALLENGE_DEPOSIT, 42L));

        assertEquals(100, user.getCoinBalance());       // 잔액 불변(클램핑 차감 안 함)
        verify(coinTransactionRepository, never()).save(any());
    }

    @Test
    void chargeStrict_negativeAmount_isRejected() {
        assertThrows(IllegalArgumentException.class, () ->
                coinService.chargeStrict(1L, -1, CoinTransactionReason.CHALLENGE_DEPOSIT, 42L));
        verify(userRepository, never()).findByIdForUpdate(any());
    }
}
