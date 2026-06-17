package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.dto.CheckInResponse;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class ChallengeCheckInService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final TeamRepository teamRepository;
    private final GpsVerificationEvaluator gpsVerificationEvaluator;

    public CheckInResponse recordCheckIn(Long userId, Long challengeId, double currentLat, double currentLng) {
        // 1. CONFIRMED 참여자 조회
        ChallengeParticipant participant = participantRepository
                .findConfirmedByUserAndChallenge(challengeId, userId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "ChallengeParticipant not found for userId=" + userId + ", challengeId=" + challengeId));

        // 2. KST 기준 오늘 날짜
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));

        // 3. 기존 SUCCESS 레코드 있으면 멱등 반환
        Optional<ChallengeCheckIn> existing = checkInRepository
                .findByParticipantIdAndCheckInDate(participant.getId(), today);
        if (existing.isPresent() && existing.get().getStatus() == CheckInStatus.SUCCESS) {
            return CheckInResponse.from(existing.get());
        }

        // 4. GPS 판정
        boolean withinRadius = gpsVerificationEvaluator.isWithinRadius(
                participant.getGpsLat(),
                participant.getGpsLng(),
                participant.getGpsRadiusMeters(),
                currentLat,
                currentLng
        );
        CheckInStatus status = withinRadius ? CheckInStatus.SUCCESS : CheckInStatus.FAILED;
        LocalDateTime verifiedAt = withinRadius ? LocalDateTime.now() : null;

        // 5. 체크인 저장
        ChallengeCheckIn checkIn = ChallengeCheckIn.builder()
                .participantId(participant.getId())
                .challengeId(challengeId)
                .teamId(participant.getTeamId())
                .checkInDate(today)
                .status(status)
                .verifiedAt(verifiedAt)
                .currentLat(currentLat)
                .currentLng(currentLng)
                .build();
        ChallengeCheckIn saved = checkInRepository.save(checkIn);

        // 6. SUCCESS인 경우 팀 participation_rate 캐시 갱신
        if (status == CheckInStatus.SUCCESS) {
            updateTeamParticipationRate(participant.getTeamId());
        }

        return CheckInResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public List<CheckInResponse> getTeamCheckIns(Long challengeId, LocalDate date) {
        return checkInRepository.findByChallengeIdAndCheckInDate(challengeId, date)
                .stream()
                .map(CheckInResponse::from)
                .collect(Collectors.toList());
    }

    private void updateTeamParticipationRate(Long teamId) {
        Team team = teamRepository.findById(teamId)
                .orElseThrow(() -> new ResourceNotFoundException("Team", teamId));

        long totalMembers = participantRepository.findByTeamId(teamId).size();
        if (totalMembers == 0) return;

        // 오늘 날짜 기준 SUCCESS 누적 체크인 수로 비율 계산
        // 전체 기간에 걸친 누적 비율: SUCCESS / (totalMembers * 경과일수)
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));
        long successCount = checkInRepository.findByTeamIdAndCheckInDate(teamId, today)
                .stream()
                .filter(c -> c.getStatus() == CheckInStatus.SUCCESS)
                .count();

        BigDecimal rate = BigDecimal.valueOf(successCount)
                .divide(BigDecimal.valueOf(totalMembers), 4, RoundingMode.HALF_UP);

        team.updateParticipationRate(rate);
        teamRepository.save(team);
    }
}
