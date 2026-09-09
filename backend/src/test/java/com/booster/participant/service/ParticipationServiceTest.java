package com.booster.participant.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.dto.ParticipantResponse;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.contract.CoinService;
import com.booster.shared.contract.CoinTransactionReason;
import com.booster.team.service.TeamFormationService;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import com.booster.shared.common.BusinessException;

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

    /** 참가자 목록·승인 응답에 신청자 닉네임을 채우는 데 쓴다. */
    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private ParticipationService participationService;

    private final Long leaderId = 1L;
    private final Long challengeId = 10L;
    private final Long participantId = 100L;

    // ── 이슈 3: approveParticipation - 챌린지가 ACTIVE일 때 409 충돌(BusinessException) 기대 ──

    @Test
    void approveParticipation_whenChallengeIsActive_shouldThrowConflict() {
        Challenge challenge = mock(Challenge.class);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(BusinessException.class,
                () -> participationService.approveParticipation(leaderId, challengeId, participantId));
    }

    @Test
    void approveParticipation_whenChallengeIsEnded_shouldThrowConflict() {
        Challenge challenge = mock(Challenge.class);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(BusinessException.class,
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

    // ── 이슈 I15(BS-39): 회원 탈퇴 시 시작 전(READY) 챌린지 참여 환불·정리 ──
    // 예전엔 withdraw가 deactivate만 해서 탈퇴 후에도 참여·예치금이 남아 정산에 좀비로 집계됐다.

    @Test
    void cancelActiveParticipationsForWithdrawal_whenReadyConfirmed_shouldRefundAndCancel() {
        Long userId = 99L;
        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.READY);
        when(challenge.getDepositCoins()).thenReturn(100L);

        ChallengeParticipant confirmed = ChallengeParticipant.builder()
                .challenge(challenge).userId(userId)
                .status(ParticipantStatus.CONFIRMED).gpsLocked(false).build();
        when(participantRepository.findByUserId(userId)).thenReturn(List.of(confirmed));
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));
        when(participantRepository.findByChallengeIdAndUserId(challengeId, userId))
                .thenReturn(Optional.of(confirmed));

        participationService.cancelActiveParticipationsForWithdrawal(userId);

        // READY 챌린지 참여는 예치금 환불 1회 + 참여 취소
        verify(coinService).credit(eq(userId), eq(100L),
                eq(CoinTransactionReason.DEPOSIT_CANCEL_REFUND), eq(challengeId));
        org.junit.jupiter.api.Assertions.assertEquals(ParticipantStatus.CANCELLED, confirmed.getStatus());
    }

    @Test
    void cancelActiveParticipationsForWithdrawal_whenChallengeActive_shouldNotRefund() {
        Long userId = 99L;
        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);

        ChallengeParticipant confirmed = ChallengeParticipant.builder()
                .challenge(challenge).userId(userId)
                .status(ParticipantStatus.CONFIRMED).gpsLocked(false).build();
        when(participantRepository.findByUserId(userId)).thenReturn(List.of(confirmed));
        when(challengeRepository.findByIdWithLock(challengeId)).thenReturn(Optional.of(challenge));

        participationService.cancelActiveParticipationsForWithdrawal(userId);

        // 시작된(ACTIVE) 챌린지는 기존 취소규칙대로 환불 없음
        verify(coinService, never()).credit(anyLong(), anyLong(), any(), anyLong());
    }

    // ── 방장 승인 화면은 신청자를 알아볼 수 있어야 한다 ──
    // 닉네임이 없으면 앱이 "참가자 #7"로만 표시해서 누구를 승인하는지 알 수 없었다.

    @Test
    void getParticipants_shouldFillApplicantNickname() {
        Long applicantId = 7L;
        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
        when(challenge.getCreatedBy()).thenReturn(leaderId);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant pending = ChallengeParticipant.builder()
                .challenge(challenge).userId(applicantId)
                .status(ParticipantStatus.PENDING).gpsLocked(false).build();
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.PENDING))
                .thenReturn(List.of(pending));

        User applicant = mock(User.class);
        when(applicant.getId()).thenReturn(applicantId);
        when(applicant.getNickname()).thenReturn("부스터");
        when(userRepository.findAllById(List.of(applicantId))).thenReturn(List.of(applicant));

        List<ParticipantResponse> result =
                participationService.getParticipants(leaderId, challengeId, ParticipantStatus.PENDING);

        org.junit.jupiter.api.Assertions.assertEquals("부스터", result.get(0).getNickname());
    }
}
