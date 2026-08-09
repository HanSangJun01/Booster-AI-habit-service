package com.booster.settlement.service;

import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 이슈 1: SettlementFailureRecorder.recordFailure() TDD 테스트
 * 수정 전: stub 구현체가 아무것도 하지 않으므로 verify 실패.
 * 수정 후: 전체 구현으로 findByChallengeId, fail(), save 순서대로 호출 → 통과.
 */
@ExtendWith(MockitoExtension.class)
class SettlementFailureRecorderTest {

    @Mock private SettlementRepository settlementRepository;
    @InjectMocks private SettlementFailureRecorder failureRecorder;

    @Test
    void recordFailure_shouldSaveSettlementWithFailedStatus() {
        Long challengeId = 100L;
        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());
        when(settlementRepository.save(any(Settlement.class))).thenAnswer(inv -> inv.getArgument(0));

        failureRecorder.recordFailure(challengeId);

        ArgumentCaptor<Settlement> captor = ArgumentCaptor.forClass(Settlement.class);
        verify(settlementRepository).save(captor.capture());
        assertEquals(SettlementStatus.FAILED, captor.getValue().getStatus());
    }
}
