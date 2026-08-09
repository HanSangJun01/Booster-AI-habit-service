package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.*;

/**
 * 이슈 3: ENDED 고착 — 정산 실패 후 재시도 없음 TDD 테스트
 * 수정 전: retryFailedSettlements() 메서드 자체가 없으므로 컴파일 에러.
 * 수정 후: FAILED settlement인 경우에만 settleChallenge 재호출.
 */
@ExtendWith(MockitoExtension.class)
class ChallengeEndSchedulerTest {

    @Mock private ChallengeRepository challengeRepository;
    @Mock private SettlementService settlementService;
    @Mock private SettlementRepository settlementRepository;
    @Mock private SettlementFailureRecorder failureRecorder;

    @InjectMocks
    private ChallengeEndScheduler scheduler;

    @Test
    void retryFailedSettlements_whenSettlementFailed_shouldCallSettleChallenge() {
        Challenge endedChallenge = mock(Challenge.class);
        when(endedChallenge.getId()).thenReturn(1L);
        when(challengeRepository.findByStatus(ChallengeStatus.ENDED))
                .thenReturn(List.of(endedChallenge));

        Settlement failedSettlement = mock(Settlement.class);
        when(failedSettlement.getStatus()).thenReturn(SettlementStatus.FAILED);
        when(settlementRepository.findByChallengeId(1L))
                .thenReturn(Optional.of(failedSettlement));

        scheduler.retryFailedSettlements();

        verify(settlementService).settleChallenge(1L);
    }

    @Test
    void retryFailedSettlements_whenSettlementCompleted_shouldNotRetry() {
        Challenge endedChallenge = mock(Challenge.class);
        when(endedChallenge.getId()).thenReturn(2L);
        when(challengeRepository.findByStatus(ChallengeStatus.ENDED))
                .thenReturn(List.of(endedChallenge));

        Settlement completedSettlement = mock(Settlement.class);
        when(completedSettlement.getStatus()).thenReturn(SettlementStatus.COMPLETED);
        when(settlementRepository.findByChallengeId(2L))
                .thenReturn(Optional.of(completedSettlement));

        scheduler.retryFailedSettlements();

        verify(settlementService, never()).settleChallenge(any());
    }

    @Test
    void retryFailedSettlements_whenNoSettlementExists_shouldCallSettleChallenge() {
        Challenge endedChallenge = mock(Challenge.class);
        when(endedChallenge.getId()).thenReturn(3L);
        when(challengeRepository.findByStatus(ChallengeStatus.ENDED))
                .thenReturn(List.of(endedChallenge));

        when(settlementRepository.findByChallengeId(3L)).thenReturn(Optional.empty());

        scheduler.retryFailedSettlements();

        verify(settlementService).settleChallenge(3L);
    }

    /**
     * [교착 수정] 정산 실패 시 FAILED 기록은 settleChallenge의 트랜잭션이 롤백된 "이후"
     * 스케줄러가 REQUIRES_NEW로 수행한다. (서비스 내부 기록은 자신이 INSERT한 미커밋
     * PENDING 행과 unique(challenge_id) 충돌 → self-deadlock으로 스케줄러 스레드 사망)
     */
    @Test
    void retryFailedSettlements_whenSettleThrows_shouldRecordFailureAfterwards() {
        Challenge endedChallenge = mock(Challenge.class);
        when(endedChallenge.getId()).thenReturn(4L);
        when(challengeRepository.findByStatus(ChallengeStatus.ENDED))
                .thenReturn(List.of(endedChallenge));
        when(settlementRepository.findByChallengeId(4L)).thenReturn(Optional.empty());

        doThrow(new RuntimeException("settlement boom")).when(settlementService).settleChallenge(4L);

        scheduler.retryFailedSettlements();

        verify(failureRecorder).recordFailure(4L);
    }

    @Test
    void markEndedChallenges_whenSettleThrows_shouldRecordFailureAndContinue() {
        Challenge c1 = mock(Challenge.class);
        Challenge c2 = mock(Challenge.class);
        when(c1.getId()).thenReturn(5L);
        when(c2.getId()).thenReturn(6L);
        when(challengeRepository.findByStatusAndEndedAtBefore(
                eq(ChallengeStatus.ACTIVE), any())).thenReturn(List.of(c1, c2));

        doThrow(new RuntimeException("settlement boom")).when(settlementService).settleChallenge(5L);

        scheduler.markEndedChallenges();

        // 5L 실패는 FAILED로 기록되고, 다음 챌린지(6L) 처리는 계속된다
        verify(failureRecorder).recordFailure(5L);
        verify(settlementService).settleChallenge(6L);
        verify(failureRecorder, never()).recordFailure(6L);
    }
}
