package com.booster.shared.contract;

import com.booster.shared.common.InsufficientCoinException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@Profile("stub")
public class StubCoinService implements CoinService {

    private static final long STUB_BALANCE = 9999L;

    @Override
    public void deduct(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        log.info("[STUB] deduct userId={} amount={} reason={} ref={}", userId, amount, reason, referenceId);
        if (amount > STUB_BALANCE) {
            throw new InsufficientCoinException(amount, STUB_BALANCE);
        }
    }

    @Override
    public void credit(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        log.info("[STUB] credit userId={} amount={} reason={} ref={}", userId, amount, reason, referenceId);
    }

    @Override
    public long getBalance(Long userId) {
        return STUB_BALANCE;
    }
}
