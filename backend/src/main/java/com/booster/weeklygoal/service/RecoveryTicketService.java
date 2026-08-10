package com.booster.weeklygoal.service;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.shared.common.BusinessException;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;

/**
 * 구제권 지급 · 구매.
 *
 * <p>구제권은 주간 목표 미달 시 {@link WeeklyEvaluationService} 가 자동으로 소모한다. 사용자가
 * 직접 "쓴다"는 행위는 없고, 여기서는 <b>공급</b>만 다룬다.
 * <ul>
 *   <li>매월 1일 무료 1개 — 이월 없음(남아 있던 수량은 1로 초기화된다)</li>
 *   <li>코인으로 추가 구매 — 현재 구매 한도 없음</li>
 * </ul>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RecoveryTicketService {

    private final UserRepository userRepository;
    private final PersonalLocationRepository locationRepository;
    private final CoinService coinService;

    @Value("${booster.weekly.ticket-price}")
    private long ticketPrice;

    /**
     * 구제권 1개 구매. 잔액이 부족하면 {@code InsufficientCoinException}(→ 400)으로 거절한다.
     *
     * <p>사용자 행을 먼저 잠근 뒤 차감·지급을 한 트랜잭션으로 수행한다. 동시에 두 번 눌러도
     * 잔액 검사와 차감이 같은 락 안에 있어 잔액이 음수가 되지 않는다.
     *
     * @return 구매 후 보유 구제권 수
     */
    @Transactional
    public int purchase(Long userId) {
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        coinService.chargeStrict(userId, ticketPrice,
                CoinTransactionReason.RECOVERY_TICKET_PURCHASE, null);
        user.addPaidRecoveryTickets(1);

        log.info("[RecoveryTicket] purchased: userId={}, price={}, tickets={}",
                userId, ticketPrice, user.getRecoveryTickets());
        return user.getRecoveryTickets();
    }

    /**
     * 매월 1일 처리: 무료 구제권 지급 + 예약된 주간 목표 승격.
     *
     * <p>둘 다 "월 1회"라는 같은 주기를 갖고, 같은 사용자 행을 만지므로 한 트랜잭션에서 처리한다.
     * 목표 변경을 월 1회로 묶은 이유는 진행 중인 기간의 채점 기준이 흔들리지 않게 하기 위해서다
     * (주 중간에 목표를 낮춰 그 주를 통과하는 회피 차단).
     *
     * <p>같은 달에 이미 처리했으면 아무것도 하지 않는다(멱등). 사용자별 트랜잭션이라 한 명이
     * 실패해도 나머지에 영향이 없다.
     */
    @Transactional
    public boolean runMonthly(Long userId, LocalDate monthStart) {
        User user = userRepository.findByIdForUpdate(userId).orElse(null);
        if (user == null || !user.isActive()) {
            return false;
        }
        boolean granted = user.grantMonthlyRecoveryTicket(monthStart);
        if (granted) {
            // 무료 구제권을 새로 준 달에만 목표 예약을 승격한다(같은 멱등 키를 공유).
            locationRepository.findById(userId)
                    .ifPresent(PersonalLocation::applyPendingTargetIfAny);
        }
        return granted;
    }

    public long getTicketPrice() {
        return ticketPrice;
    }
}
