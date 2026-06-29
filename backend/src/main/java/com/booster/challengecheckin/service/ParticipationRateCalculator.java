package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.repository.ChallengeRepository;
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

@Service
@RequiredArgsConstructor
public class ParticipationRateCalculator {

    private final TeamRepository teamRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeRepository challengeRepository;

    /**
     * 화면용 캐시값 반환.
     */
    public BigDecimal currentRate(Long teamId) {
        return teamRepository.findById(teamId)
                .orElseThrow(() -> new ResourceNotFoundException("Team", teamId))
                .getParticipationRate();
    }

    /**
     * 날짜별 슬롯 루프 방식으로 팀의 권위적 참여율 계산 (정산용).
     * SettlementService.computeAuthoritativeRate 와 동일한 알고리즘을 사용한다.
     */
    public BigDecimal authoritativeRate(Long challengeId, Long teamId) {
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        List<ChallengeParticipant> members = participantRepository.findByTeamId(teamId);
        if (members.isEmpty()) {
            return BigDecimal.ZERO;
        }

        LocalDate startDate = challenge.getStartedAt().toLocalDate();
        int durationDays = challenge.getDurationDays();
        LocalDateTime challengeEndedAt = challenge.getEndedAt();

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

            long successCount = checkInRepository
                    .findByChallengeIdAndCheckInDate(challenge.getId(), currentDate)
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
