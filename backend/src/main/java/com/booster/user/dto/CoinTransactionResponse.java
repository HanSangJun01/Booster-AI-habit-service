package com.booster.user.dto;

import com.booster.coin.domain.CoinTransaction;
import com.booster.coin.domain.CoinTransactionReason;

import java.time.OffsetDateTime;

public record CoinTransactionResponse(
        CoinTransactionReason type,
        long amount,
        long balanceAfter,
        Long referenceId,
        OffsetDateTime createdAt
) {
    public static CoinTransactionResponse from(CoinTransaction tx) {
        return new CoinTransactionResponse(
                tx.getType(),
                tx.getAmount(),
                tx.getBalanceAfter(),
                tx.getReferenceId(),
                tx.getCreatedAt());
    }
}
