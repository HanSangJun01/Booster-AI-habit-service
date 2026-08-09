package com.booster.coin.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.OffsetDateTime;

/**
 * 코인 변동 이력(단일 진실 원천). bs-25 Principle 2:
 * SUM(amount) == User.coinBalance 가 항상 성립하도록 amount는 실제 차감/지급액(effective)을 기록한다.
 */
@Entity
@Table(name = "coin_transactions")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class CoinTransaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private CoinTransactionReason type;

    /** 부호 있는 실제 변동액 (지급 +, 차감 -). */
    @Column(nullable = false)
    private long amount;

    @Column(name = "balance_after", nullable = false)
    private long balanceAfter;

    /** 연관 도메인 식별자(선택). 예: 복귀 미션 ID. */
    @Column(name = "reference_id")
    private Long referenceId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    public static CoinTransaction of(Long userId, CoinTransactionReason type,
                                     long amount, long balanceAfter, Long referenceId) {
        return CoinTransaction.builder()
                .userId(userId)
                .type(type)
                .amount(amount)
                .balanceAfter(balanceAfter)
                .referenceId(referenceId)
                .build();
    }
}
