package com.booster.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
import org.hibernate.annotations.DynamicUpdate;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * ★동시성: {@code @DynamicUpdate} — 변경된 컬럼만 UPDATE 한다. 이게 없으면 checkIn 이
 * total_attendance 만 바꿔도 flush 시 coin_balance 까지 (읽었던 옛 값으로) 덮어써서,
 * 동시에 커밋된 CoinService 의 코인 차감을 통째로 날리는 lost update 가 발생한다(BS-30 C1).
 */
@Entity
@Table(name = "users")
@DynamicUpdate
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(nullable = false)
    private String nickname;

    @Column(name = "coin_balance", nullable = false)
    private long coinBalance;

    @Column(name = "total_attendance", nullable = false)
    private int totalAttendance;

    @Column(name = "is_active", nullable = false)
    private boolean active;

    /** 무료 구제권. 매월 1일 1개로 재설정되며 안 쓰면 사라진다(이월 없음). */
    @Column(name = "free_recovery_tickets", nullable = false)
    private int freeRecoveryTickets;

    /** 코인으로 구매한 구제권. 지불한 것이므로 소멸하지 않는다. */
    @Column(name = "paid_recovery_tickets", nullable = false)
    private int paidRecoveryTickets;

    /** 무료 구제권을 마지막으로 지급한 달(해당 월 1일). 월 1회 지급의 멱등 키. */
    @Column(name = "tickets_granted_month")
    private LocalDate ticketsGrantedMonth;

    @CreationTimestamp
    @Column(name = "joined_at", nullable = false, updatable = false)
    private OffsetDateTime joinedAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    public static User create(String email, String passwordHash, String nickname) {
        return User.builder()
                .email(email)
                .passwordHash(passwordHash)
                .nickname(nickname)
                .coinBalance(0L)
                .totalAttendance(0)
                .active(true)
                .freeRecoveryTickets(1)   // 가입 시 무료 구제권 1개
                .paidRecoveryTickets(0)
                .build();
    }

    /** 코인 잔액 변동. CoinService를 통해서만 호출(단일 진실 원천). */
    public void addCoins(long delta) {
        this.coinBalance += delta;
    }

    public void increaseAttendance() {
        this.totalAttendance += 1;
    }

    /** 보유 구제권 합계(무료 + 구매). */
    public int getRecoveryTickets() {
        return this.freeRecoveryTickets + this.paidRecoveryTickets;
    }

    /**
     * 무료 구제권 월 1회 지급. 같은 달에 이미 지급했으면 아무것도 하지 않는다(멱등).
     *
     * <p>무료분만 1개로 재설정한다 — 안 쓴 무료 구제권은 이월되지 않는다. 반면 <b>코인으로 산
     * 구제권은 건드리지 않는다.</b> 지불한 대가가 달이 바뀌었다는 이유로 사라지면 안 되기 때문이다.
     *
     * @param monthStart 대상 월의 1일
     * @return 실제로 지급했으면 true
     */
    public boolean grantMonthlyRecoveryTicket(LocalDate monthStart) {
        if (monthStart.equals(this.ticketsGrantedMonth)) {
            return false;
        }
        this.freeRecoveryTickets = 1;
        this.ticketsGrantedMonth = monthStart;
        return true;
    }

    /** 구제권 구매분 추가(구매 한도 없음). */
    public void addPaidRecoveryTickets(int count) {
        this.paidRecoveryTickets += count;
    }

    /**
     * 구제권 1개 소모. 주간 채점에서 미달일 때 자동 호출된다.
     *
     * <p>무료분을 먼저 쓴다 — 무료분은 월말에 어차피 사라지므로 그게 사용자에게 유리하다.
     *
     * @return 소모했으면 true, 보유량이 0이면 false
     */
    public boolean consumeRecoveryTicket() {
        if (this.freeRecoveryTickets > 0) {
            this.freeRecoveryTickets -= 1;
            return true;
        }
        if (this.paidRecoveryTickets > 0) {
            this.paidRecoveryTickets -= 1;
            return true;
        }
        return false;
    }

    public void changeNickname(String nickname) {
        this.nickname = nickname;
    }

    public void deactivate() {
        this.active = false;
    }
}
