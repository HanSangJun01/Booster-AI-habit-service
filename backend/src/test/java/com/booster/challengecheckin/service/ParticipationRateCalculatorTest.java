package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.team.repository.TeamRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 이슈: ParticipationRateCalculator.authoritativeRate()에서
 * ci.getTeamId().equals(teamId) 호출 시 ci.getTeamId()가 null이면 NPE 발생.
 * V8 마이그레이션 이후 team_id nullable 허용으로 인한 버그.
 */
@ExtendWith(MockitoExtension.class)
class ParticipationRateCalculatorTest {

    @Mock private TeamRepository teamRepository;
    @Mock private ChallengeParticipantRepository participantRepository;
    @Mock private ChallengeCheckInRepository checkInRepository;
    @Mock private ChallengeRepository challengeRepository;

    @InjectMocks
    private ParticipationRateCalculator calculator;

    /**
     * 버그 재현: teamId가 null인 체크인 row가 포함될 때
     * ci.getTeamId().equals(teamId)에서 NullPointerException 발생.
     * fix 후에는 teamId.equals(ci.getTeamId())로 null-safe하게 처리된다.
     */
    @Test
    void authoritativeRate_withNullTeamIdCheckIn_shouldNotThrowNPE() {
        // given
        Long challengeId = 200L;
        Long teamId = 1L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
        // 1일 챌린지: 어제 시작, 오늘 종료
        when(challenge.getStartedAt()).thenReturn(LocalDateTime.now().minusDays(1));
        when(challenge.getDurationDays()).thenReturn(1);
        when(challenge.getEndedAt()).thenReturn(LocalDateTime.now().plusHours(1));
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant member = ChallengeParticipant.builder()
                .userId(10L)
                .status(ParticipantStatus.CONFIRMED)
                .build();
        when(participantRepository.findByTeamId(teamId)).thenReturn(List.of(member));

        // V8 마이그레이션으로 생긴 teamId=null 체크인 row
        ChallengeCheckIn checkInWithNullTeam = ChallengeCheckIn.builder()
                .challengeId(challengeId)
                .participantId(99L)
                .teamId(null)
                .checkInDate(LocalDate.now().minusDays(1))
                .status(CheckInStatus.SUCCESS)
                .build();

        // 정상 체크인 (teamId 일치, SUCCESS)
        ChallengeCheckIn normalCheckIn = ChallengeCheckIn.builder()
                .challengeId(challengeId)
                .participantId(10L)
                .teamId(teamId)
                .checkInDate(LocalDate.now().minusDays(1))
                .status(CheckInStatus.SUCCESS)
                .build();

        when(checkInRepository.findByChallengeIdAndCheckInDate(eq(challengeId), any(LocalDate.class)))
                .thenReturn(List.of(checkInWithNullTeam, normalCheckIn));

        // when & then
        // 수정 전: ci.getTeamId().equals(teamId) → NPE → assertDoesNotThrow FAILS (버그 재현)
        // 수정 후: teamId.equals(ci.getTeamId()) → false (null-safe) → 통과
        BigDecimal result = assertDoesNotThrow(() -> calculator.authoritativeRate(challengeId, teamId));

        // null teamId row는 필터링, normalCheckIn만 카운트 → 1/1 = 1.0000
        assertEquals(new BigDecimal("1.0000"), result);
    }
}
