package com.booster.shared.contract;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * B축 {@link CoinService} 포트 → A축 실제 코인 서비스({@link com.booster.coin.service.CoinService}) 어댑터.
 *
 * <p>contract 사유 enum을 A축 통합 사유 enum으로 이름 매핑해 위임한다.
 *
 * <p>contract의 {@code deduct}는 "잔액 부족 시 예외"(챌린지 참가 차단) 시맨틱을 요구한다. A축
 * {@code charge}는 클램핑(예외 없음)이므로, 잔액검사+차감을 한 트랜잭션·행 락으로 원자화한
 * {@code chargeStrict}에 위임한다(TOCTOU 해소).
 */
@Component
@RequiredArgsConstructor
public class CoinServiceAdapter implements CoinService {

    private final com.booster.coin.service.CoinService coinService;

    @Override
    public void deduct(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        coinService.chargeStrict(userId, amount, map(reason), referenceId);
    }

    @Override
    public void credit(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        coinService.grant(userId, amount, map(reason), referenceId);
    }

    @Override
    public long getBalance(Long userId) {
        return coinService.getBalance(userId);
    }

    private static com.booster.coin.domain.CoinTransactionReason map(CoinTransactionReason reason) {
        return switch (reason) {
            case CHALLENGE_DEPOSIT -> com.booster.coin.domain.CoinTransactionReason.CHALLENGE_DEPOSIT;
            case SETTLEMENT_WIN -> com.booster.coin.domain.CoinTransactionReason.SETTLEMENT_WIN;
            case DEPOSIT_REFUND -> com.booster.coin.domain.CoinTransactionReason.DEPOSIT_REFUND;
            case DEPOSIT_CANCEL_REFUND -> com.booster.coin.domain.CoinTransactionReason.DEPOSIT_CANCEL_REFUND;
        };
    }
}
