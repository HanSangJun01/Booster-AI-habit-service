package com.booster.participant.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.contract.CoinService;
import com.booster.shared.contract.CoinTransactionReason;
import com.booster.team.service.TeamFormationService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ParticipationServiceTest {

    @Mock
    private ChallengeRepository challengeRepository;

    @Mock
    private ChallengeParticipantRepository participantRepository;

    @Mock
    private CoinService coinService;

    @Mock
    private TeamFormationService teamFormationService;

    @InjectMocks
    private ParticipationService participationService;

    private final Long leaderId = 1L;
    private final Long challengeId = 10L;
    private final Long participantId = 100L;

    // ── 이슈 3: approveParticipation - 챌린지가 ACTIVE일 때 IllegalStateException 기대 ──

    @Test
    void approveParticipation_whenChallengeIsActive_shouldThrowIllegalStateException() {
        Challenge challenge = mock(Challenge.class);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(IllegalStateException.class,
                () -> participationService.approveParticipation(leaderId, challengeId, participantId));
    }

    @Test
    void approveParticipation_whenChallengeIsEnded_shouldThrowIllegalStateException() {
        Challenge challenge = mock(Challenge.class);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(IllegalStateException.class,
                () -> participationService.approveParticipation(leaderId, challengeId, participantId));
    }

    @Test
    void approveParticipation_whenChallengeIsReady_shouldProceedNormally() {
        Challenge challenge = mock(Challenge.class);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.READY);
        when(challenge.getMaxParticipants()).thenReturn(10);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant participant = ChallengeParticipant.builder()
                .challenge(challenge)
                .userId(99L)
                .status(ParticipantStatus.PENDING)
                .gpsLocked(false)
                .build();
        when(participantRepository.findById(participantId)).thenReturn(Optional.of(participant));
        when(participantRepository.countByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED))
                .thenReturn(0L);

        // READY 상태이므로 예외 없이 통과해야 함
        participationService.approveParticipation(leaderId, challengeId, participantId);

        verify(teamFormationService).formTeamsIfReady(challengeId);
    }

    // ── 이슈 I10(BS-39): PENDING 참여자 취소 시에도 보증금 환불돼야 ──
    // 참여 시 코인은 무조건 차감되므로(LEADER 승인형=PENDING) 취소하면 환불해야 한다.
    // 예전엔 CONFIRMED만 환불해 PENDING 참여자가 보증금을 잃었다.

    @Test
    void cancelParticipation_whenPending_shouldRefundDeposit() {
        Long userId = 99L;
        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.READY);
        when(challenge.getDepositCoins()).thenReturn(100L);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant pending = ChallengeParticipant.builder()
                .challenge(challenge).userId(userId)
                .status(ParticipantStatus.PENDING).gpsLocked(false).build();
        when(participantRepository.findByChallengeIdAndUserId(challengeId, userId))
                .thenReturn(Optional.of(pending));

        participationService.cancelParticipation(userId, challengeId);

        // PENDING도 환불 1회 호출돼야 한다
        verify(coinService).credit(eq(userId), eq(100L),
                eq(CoinTransactionReason.DEPOSIT_CANCEL_REFUND), eq(challengeId));
    }

    @Test
    void cancelParticipation_whenAlreadyCancelled_shouldNotRefund() {
        Long userId = 99L;
        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.READY);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant cancelled = ChallengeParticipant.builder()
                .challenge(challenge).userId(userId)
                .status(ParticipantStatus.CANCELLED).gpsLocked(false).build();
        when(participantRepository.findByChallengeIdAndUserId(challengeId, userId))
                .thenReturn(Optional.of(cancelled));

        participationService.cancelParticipation(userId, challengeId);

        // 이미 CANCELLED면 재환불 없어야 한다(이중 환불 방지)
        verify(coinService, never()).credit(anyLong(), anyLong(), any(), anyLong());
    }
}
