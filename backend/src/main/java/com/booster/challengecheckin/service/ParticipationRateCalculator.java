package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ParticipationRateCalculator {

    private final TeamRepository teamRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeRepository challengeRepository;

    public BigDecimal currentRate(Long teamId) {
        return teamRepository.findById(teamId)
                .orElseThrow(() -> new ResourceNotFoundException("Team", teamId))
                .getParticipationRate();
    }

    public BigDecimal authoritativeRate(Long challengeId, Long teamId) {
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        List<ChallengeParticipant> members = participantRepository.findByTeamId(teamId);
        if (members.isEmpty()) {
            return BigDecimal.ZERO;
        }

        LocalDate startDate = challenge.getStartedAt().toLocalDate();
        int durationDays = challenge.getDurationDays();
        LocalDate endDate = startDate.plusDays(durationDays - 1);
        LocalDateTime challengeEndedAt = challenge.getEndedAt();

        // 전체 기간 체크인을 한 번에 조회하여 N+1 제거
        Map<LocalDate, List<ChallengeCheckIn>> checkInsByDate =
                checkInRepository.findByChallengeIdAndCheckInDateBetween(challenge.getId(), startDate, endDate)
                        .stream()
                        .collect(Collectors.groupingBy(ChallengeCheckIn::getCheckInDate));

        long totalNumerator = 0L;
        long totalDenominator = 0L;

        for (int dayOffset = 0; dayOffset < durationDays; dayOffset++) {
            LocalDate currentDate = startDate.plusDays(dayOffset);

            long activeMemberCount = members.stream()
                    .filter(p -> {
                        if (p.getStatus() == ParticipantStatus.LEFT) {
                            LocalDateTime activeUntil = p.getActiveUntil();
                            if (activeUntil == null) {
                                return !currentDate.isAfter(challengeEndedAt.toLocalDate());
                            }
                            return !currentDate.isAfter(activeUntil.toLocalDate());
                        } else if (p.getStatus() == ParticipantStatus.CONFIRMED) {
                            return !currentDate.isAfter(challengeEndedAt.toLocalDate());
                        }
                        return false;
                    })
                    .count();

            if (activeMemberCount == 0) {
                continue;
            }

            long successCount = checkInsByDate.getOrDefault(currentDate, List.of())
                    .stream()
                    .filter(ci -> teamId.equals(ci.getTeamId())
                            && ci.getStatus() == CheckInStatus.SUCCESS)
                    .count();

            totalNumerator += successCount;
            totalDenominator += activeMemberCount;
        }

        if (totalDenominator == 0) {
            return BigDecimal.ZERO;
        }

        return BigDecimal.valueOf(totalNumerator)
                .divide(BigDecimal.valueOf(totalDenominator), 4, RoundingMode.HALF_UP);
    }
}
