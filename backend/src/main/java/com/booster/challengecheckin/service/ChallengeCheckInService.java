package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.domain.GpsVerificationResult;
import com.booster.challengecheckin.domain.VerificationDecision;
import com.booster.challengecheckin.domain.VerificationSubmission;
import com.booster.challengecheckin.dto.CheckInResponse;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.challengecheckin.repository.GpsVerificationResultRepository;
import com.booster.challengecheckin.repository.VerificationDecisionRepository;
import com.booster.challengecheckin.repository.VerificationSubmissionRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional
public class ChallengeCheckInService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final TeamRepository teamRepository;
    private final GpsVerificationEvaluator gpsVerificationEvaluator;
    private final VerificationSubmissionRepository submissionRepository;
    private final GpsVerificationResultRepository gpsResultRepository;
    private final VerificationDecisionRepository decisionRepository;

    public CheckInResponse recordCheckIn(Long userId, Long challengeId, double submittedLat, double submittedLng) {
        log.info("CheckIn requested: userId={}, challengeId={}", userId, challengeId);

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
            log.debug("CheckIn already SUCCESS, skipping: participantId={}", participant.getId());
            return CheckInResponse.from(existing.get());
        }

        // 4. 체크인 레코드 생성 (PENDING → 판정 후 SUCCESS/FAILED로 갱신)
        ChallengeCheckIn checkIn = existing.orElseGet(() -> checkInRepository.save(
                ChallengeCheckIn.builder()
                        .participantId(participant.getId())
                        .challengeId(challengeId)
                        .teamId(participant.getTeamId())
                        .checkInDate(today)
                        .status(CheckInStatus.PENDING)
                        .build()));

        // 5. VerificationSubmission 생성
        int attemptNumber = submissionRepository.countByCheckInId(checkIn.getId()) + 1;
        VerificationSubmission submission = submissionRepository.save(
                VerificationSubmission.builder()
                        .checkInId(checkIn.getId())
                        .submittedLat(submittedLat)
                        .submittedLng(submittedLng)
                        .attemptNumber(attemptNumber)
                        .build());

        // 6. GPS 판정 → GpsVerificationResult 저장
        double distanceMeters = gpsVerificationEvaluator.calculateDistanceMeters(
                participant.getGpsLat(), participant.getGpsLng(), submittedLat, submittedLng);
        boolean withinRadius = distanceMeters <= participant.getGpsRadiusMeters();

        gpsResultRepository.save(
                GpsVerificationResult.builder()
                        .submissionId(submission.getId())
                        .targetLat(participant.getGpsLat())
                        .targetLng(participant.getGpsLng())
                        .radiusMeters(participant.getGpsRadiusMeters())
                        .distanceMeters(BigDecimal.valueOf(distanceMeters).setScale(2, RoundingMode.HALF_UP))
                        .isWithinRadius(withinRadius)
                        .build());

        // 7. VerificationDecision 저장 (MVP: GPS 결과만으로 최종 판정)
        String failureReason = withinRadius ? null : "GPS_OUT_OF_RADIUS";
        decisionRepository.save(
                VerificationDecision.builder()
                        .submissionId(submission.getId())
                        .finalPassed(withinRadius)
                        .failureReason(failureReason)
                        .build());

        // 8. ChallengeCheckIn 상태 갱신
        CheckInStatus finalStatus = withinRadius ? CheckInStatus.SUCCESS : CheckInStatus.FAILED;
        LocalDateTime verifiedAt = withinRadius ? LocalDateTime.now() : null;
        checkIn.updateStatus(finalStatus, verifiedAt);
        ChallengeCheckIn saved = checkInRepository.save(checkIn);

        if (withinRadius) {
            log.info("CheckIn SUCCESS: participantId={}, date={}", participant.getId(), today);
            if (participant.getTeamId() != null) {
                updateTeamParticipationRate(participant.getTeamId());
            }
        } else {
            log.info("CheckIn FAILED (GPS): participantId={}, date={}", participant.getId(), today);
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
