package com.booster.shared.contract;

import com.booster.shared.common.InsufficientCoinException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * B축 {@link CoinService} 포트 → A축 실제 코인 서비스({@link com.booster.coin.service.CoinService}) 어댑터.
 *
 * <p>contract 사유 enum을 A축 통합 사유 enum으로 이름 매핑해 위임한다.
 *
 * <p>주의: A축 {@code charge}는 잔액까지만 차감(클램핑)하고 예외를 던지지 않는다. 그러나 contract의
 * {@code deduct}는 "잔액 부족 시 예외" 시맨틱(챌린지 참가 차단)을 요구하므로, 여기서 사전 잔액 검사로
 * {@link InsufficientCoinException}을 던져 계약을 보존한다.
 * (사전검사→charge 사이의 TOCTOU를 원자적으로 막으려면 A축 charge에 strict 옵션 추가가 후속 과제.)
 */
@Component
@RequiredArgsConstructor
public class CoinServiceAdapter implements CoinService {

    private final com.booster.coin.service.CoinService coinService;

    @Override
    public void deduct(Long userId, long amount, CoinTransactionReason reason, Long referenceId) {
        long balance = coinService.getBalance(userId);
        if (balance < amount) {
            throw new InsufficientCoinException(amount, balance);
        }
        coinService.charge(userId, amount, map(reason), referenceId);
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
