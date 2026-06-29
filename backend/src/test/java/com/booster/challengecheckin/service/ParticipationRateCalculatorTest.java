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

@ExtendWith(MockitoExtension.class)
class ParticipationRateCalculatorTest {

    @Mock private TeamRepository teamRepository;
    @Mock private ChallengeParticipantRepository participantRepository;
    @Mock private ChallengeCheckInRepository checkInRepository;
    @Mock private ChallengeRepository challengeRepository;

    @InjectMocks
    private ParticipationRateCalculator calculator;

    /**
     * 버그 재현: teamId가 null인 체크인 row가 포함될 때 NPE 발생.
     * 수정 전: ci.getTeamId().equals(teamId) → NPE.
     * 수정 후: teamId.equals(ci.getTeamId()) → false (null-safe) → 통과.
     */
    @Test
    void authoritativeRate_withNullTeamIdCheckIn_shouldNotThrowNPE() {
        Long challengeId = 200L;
        Long teamId = 1L;

        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
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

        when(checkInRepository.findByChallengeIdAndCheckInDateBetween(eq(challengeId), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of(checkInWithNullTeam, normalCheckIn));

        // null teamId row는 필터링, normalCheckIn만 카운트 → 1/1 = 1.0000
        BigDecimal result = assertDoesNotThrow(() -> calculator.authoritativeRate(challengeId, teamId));
        assertEquals(new BigDecimal("1.0000"), result);
    }

    /**
     * N+1 재현: 3일 챌린지에서 날짜마다 DB 쿼리를 발생시키는 문제.
     * 수정 전: findByChallengeIdAndCheckInDate 3번 호출 (durationDays에 비례).
     * 수정 후: findByChallengeIdAndCheckInDateBetween 1번 호출, findByChallengeIdAndCheckInDate 0번.
     */
    @Test
    void authoritativeRate_shouldFetchAllCheckInsInOneQuery_notPerDay() {
        Long challengeId = 300L;
        Long teamId = 5L;
        LocalDate startDate = LocalDate.now().minusDays(3);

        Challenge challenge = mock(Challenge.class);
        when(challenge.getId()).thenReturn(challengeId);
        when(challenge.getStartedAt()).thenReturn(startDate.atStartOfDay());
        when(challenge.getDurationDays()).thenReturn(3);
        when(challenge.getEndedAt()).thenReturn(LocalDate.now().atStartOfDay());
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        ChallengeParticipant member = ChallengeParticipant.builder()
                .userId(20L)
                .status(ParticipantStatus.CONFIRMED)
                .build();
        when(participantRepository.findByTeamId(teamId)).thenReturn(List.of(member));

        when(checkInRepository.findByChallengeIdAndCheckInDateBetween(eq(challengeId), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());

        calculator.authoritativeRate(challengeId, teamId);

        // N+1 제거 확인: per-day 쿼리 0번, 전체 기간 단일 조회 1번
        verify(checkInRepository, never()).findByChallengeIdAndCheckInDate(any(), any());
        verify(checkInRepository, times(1))
                .findByChallengeIdAndCheckInDateBetween(eq(challengeId), any(LocalDate.class), any(LocalDate.class));
    }
}
