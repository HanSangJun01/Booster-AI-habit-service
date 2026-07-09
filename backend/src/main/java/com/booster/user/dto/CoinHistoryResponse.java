package com.booster.user.dto;

import java.util.List;

public record CoinHistoryResponse(
        List<CoinTransactionResponse> transactions,
        long totalCount
) {
}
