package com.booster.concurrency;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import com.booster.settlement.service.SettlementService;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C7] 정산 retry(FAILED) 경로의 이중 지급(double-award) 레이스를 "실패하는 통합 테스트(RED)"로 고정.
 *
 * <p>멱등 게이트는 기존 정산이 COMPLETED/PENDING이면 skip한다. 신규 정산은 settlement.challenge_id
 * unique 제약이 동시 INSERT를 직렬화한다. <b>그러나 재시도 경로(기존 정산 FAILED)는 INSERT가 없어</b>
 * unique 제약이 걸리지 않는다 → 두 호출자가 동시에 게이트를 통과해 각각 승팀에게 코인을 지급 →
 * <b>SETTLEMENT_WIN 이중 지급</b>.
 *
 * <p>재현: ENDED 챌린지 + 기존 FAILED 정산 + 2팀(승/패) 참여자를 만든 뒤,
 * {@code settleChallenge(challengeId)}를 N개 스레드에서 <b>동시</b> 호출한다.
 * 올바른 동작: 승자는 SETTLEMENT_WIN을 <b>정확히 1회</b>만 받는다(총 지급 1건). 2건 이상이면 RED.
 *
 * <p>이 테스트는 스레드 레벨 동시성을 겨눈다 — {@code @SchedulerLock}은 {@code @Scheduled}
 * 진입점만 인스턴스 간 직렬화하지, 직접 서비스 호출은 막지 않는다. 이중 지급 방어선은
 * SettlementService의 FAILED→PENDING 원자적 CAS다.
 */
class C7RetryDoubleAwardTest extends ConcurrencyTestBase {

    @Autowired SettlementService settlementService;
    @Autowired ChallengeRepository challengeRepository;
    @Autowired TeamRepository teamRepository;
    @Autowired ChallengeParticipantRepository participantRepository;
    @Autowired SettlementRepository settlementRepository;
    @Autowired ChallengeCheckInRepository checkInRepository;

    private static final long DEPOSIT = 100L;

    @Test
    @DisplayName("FAILED 정산 재시도: N개 스레드 동시 호출해도 승자는 SETTLEMENT_WIN을 정확히 1회만 받아야 한다")
    void concurrentRetry_mustNotDoubleAwardSettlementWin() throws Exception {
        // --- 픽스처: ENDED 챌린지 + 승팀(체크인 성공) / 패팀 + 기존 FAILED 정산 ---
        Long winnerUserId = newUserWithLocation("c7-win-");
        Long loserUserId = newUserWithLocation("c7-lose-");

        LocalDateTime startedAt = LocalDateTime.now().minusDays(1);
        LocalDateTime endedAt = LocalDateTime.now();

        Challenge challenge = challengeRepository.save(Challenge.builder()
                .category("study")
                .title("C7 정산 재시도 이중지급 검증")
                .verificationType(VerificationType.GPS)
                .durationDays(1)
                .depositCoins(DEPOSIT)
                .visibility(ChallengeVisibility.PUBLIC)
                .approvalType(ApprovalType.AUTO)
                .status(ChallengeStatus.ENDED)
                .maxParticipants(10)
                .startedAt(startedAt)
                .endedAt(endedAt)
                .createdBy(winnerUserId)
                .build());
        Long challengeId = challenge.getId();

        Team winnerTeam = teamRepository.save(Team.builder()
                .challengeId(challengeId).name("A").initialMemberCount(1).build());
        Team loserTeam = teamRepository.save(Team.builder()
                .challengeId(challengeId).name("B").initialMemberCount(1).build());

        ChallengeParticipant winner = participantRepository.save(ChallengeParticipant.builder()
                .challenge(challenge).userId(winnerUserId).teamId(winnerTeam.getId())
                .gpsLocked(true).status(ParticipantStatus.CONFIRMED).build());
        participantRepository.save(ChallengeParticipant.builder()
                .challenge(challenge).userId(loserUserId).teamId(loserTeam.getId())
                .gpsLocked(true).status(ParticipantStatus.CONFIRMED).build());

        // 승팀만 체크인 SUCCESS → authoritativeRate: winner=1.00 > loser=0 → winner WIN 확정
        checkInRepository.save(ChallengeCheckIn.builder()
                .participantId(winner.getId()).challengeId(challengeId).teamId(winnerTeam.getId())
                .checkInDate(startedAt.toLocalDate()).status(CheckInStatus.SUCCESS)
                .verifiedAt(LocalDateTime.now()).build());

        // 기존 정산을 FAILED로 심는다 → retry 경로(INSERT 없음, unique 제약 미개입) 진입
        settlementRepository.save(Settlement.builder()
                .challengeId(challengeId).status(SettlementStatus.FAILED).build());

        long winnerBalanceBefore = coinService.getBalance(winnerUserId); // 가입 보너스 500

        // --- N개 스레드가 동시에 재시도 정산 ---
        int threads = 5;
        List<Runnable> tasks = new ArrayList<>();
        for (int i = 0; i < threads; i++) {
            tasks.add(() -> settlementService.settleChallenge(challengeId));
        }
        runConcurrently(tasks);

        // --- 검증: 승자는 SETTLEMENT_WIN을 정확히 1회만 받아야 한다 ---
        long winCount = countTxOfType(winnerUserId, CoinTransactionReason.SETTLEMENT_WIN);
        assertThat(winCount)
                .as("승자의 SETTLEMENT_WIN 지급 건수는 정확히 1이어야 한다. %d건이면 재시도 경로에서 이중 지급됨", winCount)
                .isEqualTo(1L);

        // totalPool = deposit(100) * 참여자 2명 = 200 → 승자(1명)에게 200 지급.
        long expectedPayout = DEPOSIT * 2;
        assertThat(coinService.getBalance(winnerUserId))
                .as("승자 잔액은 가입 보너스 + 정산 보상 1회분이어야 한다(이중 지급 없음)")
                .isEqualTo(winnerBalanceBefore + expectedPayout);

        assertThat(settlementRepository.findByChallengeId(challengeId))
                .get()
                .extracting(Settlement::getStatus)
                .isEqualTo(SettlementStatus.COMPLETED);
    }
}
