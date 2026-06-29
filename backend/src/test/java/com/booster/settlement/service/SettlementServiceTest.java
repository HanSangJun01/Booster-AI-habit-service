package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.service.ParticipationRateCalculator;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import com.booster.shared.contract.CoinService;
import com.booster.shared.contract.CoinTransactionReason;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SettlementServiceTest {

    @Mock private ChallengeRepository challengeRepository;
    @Mock private TeamRepository teamRepository;
    @Mock private ChallengeParticipantRepository participantRepository;
    @Mock private SettlementRepository settlementRepository;
    @Mock private CoinService coinService;
    @Mock private ParticipationRateCalculator participationRateCalculator;
    @Mock private SettlementFailureRecorder failureRecorder;

    @InjectMocks
    private SettlementService settlementService;

    /**
     * 버그 재현: DRAW 3명 중 2번째 credit에서 예외 발생 시 예외가 전파되어야 함.
     * 수정 전: catch가 예외를 삼켜 assertThrows가 실패.
     * 수정 후: 예외가 전파되어 통과.
     */
    @Test
    void settleChallenge_whenCreditThrowsOnSecondParticipant_shouldPropagateException() {
        Long challengeId = 100L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challenge.getDepositCoins()).thenReturn(1000L);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());

        Team teamA = mock(Team.class);
        Team teamB = mock(Team.class);
        when(teamA.getId()).thenReturn(1L);
        when(teamB.getId()).thenReturn(2L);
        when(teamRepository.findByChallengeId(challengeId)).thenReturn(List.of(teamA, teamB));

        when(participationRateCalculator.authoritativeRate(challengeId, 1L))
                .thenReturn(new BigDecimal("0.5000"));
        when(participationRateCalculator.authoritativeRate(challengeId, 2L))
                .thenReturn(new BigDecimal("0.5000"));

        ChallengeParticipant p1 = ChallengeParticipant.builder()
                .userId(1L).status(ParticipantStatus.CONFIRMED).build();
        ChallengeParticipant p2 = ChallengeParticipant.builder()
                .userId(2L).status(ParticipantStatus.CONFIRMED).build();
        ChallengeParticipant p3 = ChallengeParticipant.builder()
                .userId(3L).status(ParticipantStatus.CONFIRMED).build();

        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED))
                .thenReturn(new ArrayList<>(Arrays.asList(p1, p2, p3)));
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.LEFT))
                .thenReturn(new ArrayList<>());

        doThrow(new RuntimeException("Credit failed")).when(coinService)
                .credit(eq(2L), anyLong(), any(), any());

        assertThrows(RuntimeException.class, () -> settlementService.settleChallenge(challengeId));

        verify(coinService, atLeastOnce()).credit(any(), anyLong(), any(), any());
    }

    /**
     * 이슈 1: 예외 발생 시 failureRecorder.recordFailure()가 호출되어야 함.
     * 수정 전: SettlementService에 failureRecorder 필드가 없으므로 verify 실패.
     * 수정 후: catch 블록이 failureRecorder.recordFailure(challengeId)를 호출하여 통과.
     */
    @Test
    void settleChallenge_whenExceptionOccurs_shouldCallFailureRecorder() {
        Long challengeId = 300L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));
        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());

        // 팀 1개만 반환 → teams.size() < 2 → IllegalStateException 발생
        when(teamRepository.findByChallengeId(challengeId)).thenReturn(List.of(mock(Team.class)));

        assertThrows(IllegalStateException.class, () -> settlementService.settleChallenge(challengeId));

        verify(failureRecorder).recordFailure(challengeId);
    }

    /**
     * 이슈 2: PENDING 상태 settlement가 있으면 early return해야 함.
     * 수정 전: COMPLETED 체크만 있으므로 PENDING settlement가 있어도 진행되어 예외 발생.
     * 수정 후: PENDING 체크 추가로 early return → coinService.credit 호출 없음.
     */
    @Test
    void settleChallenge_whenSettlementAlreadyPending_shouldReturnEarly() {
        Long challengeId = 200L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        Settlement pendingSettlement = mock(Settlement.class);
        when(pendingSettlement.getStatus()).thenReturn(SettlementStatus.PENDING);
        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.of(pendingSettlement));

        settlementService.settleChallenge(challengeId);

        verify(coinService, never()).credit(any(), anyLong(), any(), any());
    }

    /**
     * 코인 나머지 소실 방지: totalPool이 승자 수로 나누어 떨어지지 않을 때.
     * 수정 전: perWinnerPayout = 3/2 = 1 → 각 1코인, 총 2코인 지급 (1코인 소실).
     * 수정 후: 첫 번째 승자에게 나머지 포함 → 2코인 + 1코인 = 총 3코인 지급.
     */
    @Test
    void settleChallenge_whenTotalPoolNotDivisible_remainderShouldNotBeLost() {
        Long challengeId = 400L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challenge.getDepositCoins()).thenReturn(1L); // totalPool = 1 * 3 = 3, 3 % 2 = 1 나머지
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());
        when(settlementRepository.save(any(Settlement.class))).thenAnswer(inv -> inv.getArgument(0));

        Team teamA = mock(Team.class);
        Team teamB = mock(Team.class);
        when(teamA.getId()).thenReturn(10L);
        when(teamB.getId()).thenReturn(20L);
        when(teamRepository.findByChallengeId(challengeId)).thenReturn(List.of(teamA, teamB));

        // teamA 승리 (rateA > rateB)
        when(participationRateCalculator.authoritativeRate(challengeId, 10L))
                .thenReturn(new BigDecimal("0.8000"));
        when(participationRateCalculator.authoritativeRate(challengeId, 20L))
                .thenReturn(new BigDecimal("0.5000"));

        // 전체 참여자 3명 CONFIRMED (p1, p2 = teamA 승자; p3 = teamB 패자)
        ChallengeParticipant p1 = ChallengeParticipant.builder().userId(10L).status(ParticipantStatus.CONFIRMED).build();
        ChallengeParticipant p2 = ChallengeParticipant.builder().userId(11L).status(ParticipantStatus.CONFIRMED).build();
        ChallengeParticipant p3 = ChallengeParticipant.builder().userId(12L).status(ParticipantStatus.CONFIRMED).build();

        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED))
                .thenReturn(new ArrayList<>(Arrays.asList(p1, p2, p3)));
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.LEFT))
                .thenReturn(new ArrayList<>());

        // 승팀(teamA) 참여자: p1, p2 모두 CONFIRMED
        when(participantRepository.findByTeamId(10L)).thenReturn(new ArrayList<>(Arrays.asList(p1, p2)));

        settlementService.settleChallenge(challengeId);

        // 나머지 코인 소실 없음: 첫 번째 승자 2코인(1+1), 두 번째 승자 1코인, 총 = totalPool(3)
        verify(coinService).credit(eq(10L), eq(2L), eq(CoinTransactionReason.SETTLEMENT_WIN), eq(challengeId));
        verify(coinService).credit(eq(11L), eq(1L), eq(CoinTransactionReason.SETTLEMENT_WIN), eq(challengeId));
    }

    /**
     * 승팀 전원 LEFT 시 코인 소실 방지.
     * 수정 전: winnerParticipants 비어있어 totalPool 전체 증발.
     * 수정 후: 승팀 전원 LEFT시 CONFIRMED 참여자에게 예치금 환불.
     */
    @Test
    void settleChallenge_whenAllWinnersAreLeft_totalPoolShouldNotBeLost() {
        Long challengeId = 500L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challenge.getDepositCoins()).thenReturn(100L);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());
        when(settlementRepository.save(any(Settlement.class))).thenAnswer(inv -> inv.getArgument(0));

        Team teamA = mock(Team.class);
        Team teamB = mock(Team.class);
        when(teamA.getId()).thenReturn(100L);
        when(teamB.getId()).thenReturn(200L);
        when(teamRepository.findByChallengeId(challengeId)).thenReturn(List.of(teamA, teamB));

        // teamA 승리, 하지만 teamA 참여자 전원 LEFT
        when(participationRateCalculator.authoritativeRate(challengeId, 100L))
                .thenReturn(new BigDecimal("0.9000"));
        when(participationRateCalculator.authoritativeRate(challengeId, 200L))
                .thenReturn(new BigDecimal("0.4000"));

        ChallengeParticipant winner1 = ChallengeParticipant.builder().userId(31L).status(ParticipantStatus.LEFT).build();
        ChallengeParticipant winner2 = ChallengeParticipant.builder().userId(32L).status(ParticipantStatus.LEFT).build();
        ChallengeParticipant loser = ChallengeParticipant.builder().userId(30L).status(ParticipantStatus.CONFIRMED).build();

        // allParticipants: CONFIRMED=[loser], LEFT=[winner1, winner2] → totalPool = 100 * 3 = 300
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED))
                .thenReturn(new ArrayList<>(List.of(loser)));
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.LEFT))
                .thenReturn(new ArrayList<>(Arrays.asList(winner1, winner2)));

        // 승팀 findByTeamId → 전원 LEFT → CONFIRMED 필터 후 winnerParticipants = []
        when(participantRepository.findByTeamId(100L))
                .thenReturn(new ArrayList<>(Arrays.asList(winner1, winner2)));

        settlementService.settleChallenge(challengeId);

        // CONFIRMED 참여자(loser, userId=30L)에게 예치금 100코인 환불
        verify(coinService).credit(eq(30L), eq(100L), eq(CoinTransactionReason.DEPOSIT_REFUND), eq(challengeId));
        // LEFT 참여자에게는 환불 없음
        verify(coinService, never()).credit(eq(31L), anyLong(), any(), any());
        verify(coinService, never()).credit(eq(32L), anyLong(), any(), any());
    }
}
