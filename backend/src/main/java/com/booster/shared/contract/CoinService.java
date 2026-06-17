package com.booster.shared.contract;

public interface CoinService {

    /** 코인 차감. 잔액 부족 시 InsufficientCoinException 발생. */
    void deduct(Long userId, long amount, CoinTransactionReason reason, Long referenceId);

    /** 코인 지급. */
    void credit(Long userId, long amount, CoinTransactionReason reason, Long referenceId);

    /** 현재 잔액 조회. */
    long getBalance(Long userId);
}
