package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.service.ParticipationRateCalculator;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.settlement.repository.SettlementRepository;
import com.booster.shared.contract.CoinService;
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

/**
 * 이슈: SettlementService.settleChallenge() catch 블록이 예외를 삼켜
 * 부분 코인 지급이 커밋되는 버그를 재현한다.
 */
@ExtendWith(MockitoExtension.class)
class SettlementServiceTest {

    @Mock private ChallengeRepository challengeRepository;
    @Mock private TeamRepository teamRepository;
    @Mock private ChallengeParticipantRepository participantRepository;
    @Mock private SettlementRepository settlementRepository;
    @Mock private CoinService coinService;
    @Mock private ParticipationRateCalculator participationRateCalculator;

    @InjectMocks
    private SettlementService settlementService;

    /**
     * 버그 재현: DRAW 3명 중 2번째 credit에서 예외 발생 시,
     * catch 블록이 예외를 삼키면 assertThrows가 실패한다 (버그).
     * fix 후에는 예외가 전파되어 assertThrows가 통과한다.
     */
    @Test
    void settleChallenge_whenCreditThrowsOnSecondParticipant_shouldPropagateException() {
        // given
        Long challengeId = 100L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challenge.getDepositCoins()).thenReturn(1000L);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        // 정산 기록 없음 → 새 Settlement 생성
        when(settlementRepository.findByChallengeId(challengeId)).thenReturn(Optional.empty());

        Team teamA = mock(Team.class);
        Team teamB = mock(Team.class);
        when(teamA.getId()).thenReturn(1L);
        when(teamB.getId()).thenReturn(2L);
        when(teamRepository.findByChallengeId(challengeId)).thenReturn(List.of(teamA, teamB));

        // DRAW: rateA == rateB
        when(participationRateCalculator.authoritativeRate(challengeId, 1L))
                .thenReturn(new BigDecimal("0.5000"));
        when(participationRateCalculator.authoritativeRate(challengeId, 2L))
                .thenReturn(new BigDecimal("0.5000"));

        // 3명 CONFIRMED 참여자 — mutable list 필수 (서비스에서 addAll() 호출)
        ChallengeParticipant p1 = ChallengeParticipant.builder()
                .userId(1L)
                .status(ParticipantStatus.CONFIRMED)
                .build();
        ChallengeParticipant p2 = ChallengeParticipant.builder()
                .userId(2L)
                .status(ParticipantStatus.CONFIRMED)
                .build();
        ChallengeParticipant p3 = ChallengeParticipant.builder()
                .userId(3L)
                .status(ParticipantStatus.CONFIRMED)
                .build();

        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED))
                .thenReturn(new ArrayList<>(Arrays.asList(p1, p2, p3)));
        when(participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.LEFT))
                .thenReturn(new ArrayList<>());

        // 2번째 credit (userId=2L)에서 예외
        doThrow(new RuntimeException("Credit failed")).when(coinService)
                .credit(eq(2L), anyLong(), any(), any());

        // when & then
        // 수정 전: catch가 예외를 삼키므로 이 assertThrows가 실패 → 버그 재현 확인
        // 수정 후: 예외가 전파되어 통과
        assertThrows(RuntimeException.class, () -> settlementService.settleChallenge(challengeId));

        // 부분 지급 증거: userId=1L에게는 이미 credit이 호출됨
        verify(coinService, atLeastOnce()).credit(any(), anyLong(), any(), any());
    }
}
