package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
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
import jakarta.persistence.OptimisticLockException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
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
public class ChallengeCheckInService {

    /**
     * 팀 참여율 낙관락 충돌 시 최대 재시도 횟수.
     *
     * <p>한 팀 동시 체크인 작성자 수 상한(5:5 구성상 팀 최대 5명)에 여유를 둔 값이다.
     * 팀 크기(5)와 딱 같으면 최악의 경우 한 스레드가 정확히 팀원 수만큼 재시도해야 해 마진이
     * 0이므로, 스케줄 지터·재진입 등을 흡수하도록 여유(10)를 둔다.
     *
     * <p>완화(mitigation): 소진 시 저장된 team.participationRate 는 정체될 수 있으나, 정산은
     * {@link ParticipationRateCalculator#authoritativeRate}(체크인 테이블 재계산)를 사용하므로
     * 저장 값은 표시용이며 다음 체크인에서 재계산되어 자가치유된다.
     */
    private static final int PARTICIPATION_RATE_MAX_RETRIES = 10;

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeRepository challengeRepository;
    private final TeamRepository teamRepository;
    private final GpsVerificationEvaluator gpsVerificationEvaluator;
    private final VerificationSubmissionRepository submissionRepository;
    private final GpsVerificationResultRepository gpsResultRepository;
    private final VerificationDecisionRepository decisionRepository;
    private final CheckInInsertHelper checkInInsertHelper;
    /** @Transactional/REQUIRES_NEW 프록시 경유 self-invocation용(같은 빈의 프록시 참조). */
    private final ObjectProvider<ChallengeCheckInService> self;

    /**
     * 체크인 본문은 자기 트랜잭션에서 커밋한 뒤, 참여율 갱신은 커밋된 체크인을 근거로
     * 별도 트랜잭션(낙관락 재시도)에서 수행한다. 이렇게 해야 재시도 시 re-read가 커밋된
     * 최신 상태(버전 포함)를 보게 되어 인스턴스 간 Lost Update가 방지된다.
     */
    public CheckInResponse recordCheckIn(Long userId, Long challengeId, double submittedLat, double submittedLng) {
        CheckInOutcome outcome = self().doRecordCheckIn(userId, challengeId, submittedLat, submittedLng);
        if (outcome.teamIdToUpdate() != null) {
            updateTeamParticipationRateWithRetry(outcome.teamIdToUpdate());
        }
        return outcome.response();
    }

    /** @Transactional 경계 적용을 위한 자기 프록시. 프록시가 없으면(순수 단위테스트) this 로 폴백한다. */
    private ChallengeCheckInService self() {
        ChallengeCheckInService proxy = (self != null) ? self.getIfAvailable() : null;
        return proxy != null ? proxy : this;
    }

    @Transactional
    public CheckInOutcome doRecordCheckIn(Long userId, Long challengeId, double submittedLat, double submittedLng) {
        log.info("CheckIn requested: userId={}, challengeId={}", userId, challengeId);

        // 1. CONFIRMED 참여자 조회
        ChallengeParticipant participant = participantRepository
                .findConfirmedByUserAndChallenge(challengeId, userId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "ChallengeParticipant not found for userId=" + userId + ", challengeId=" + challengeId));

        // 1-1. 챌린지 상태 확인 (ACTIVE 상태에서만 체크인 허용)
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));
        if (challenge.getStatus() != ChallengeStatus.ACTIVE) {
            throw new IllegalStateException("Check-in is only allowed when challenge is ACTIVE");
        }

        // 팀 배정 없는 참여자의 체크인 차단 — 정산 계산에서 누락되므로 허용 불가
        if (participant.getTeamId() == null) {
            throw new IllegalStateException(
                    "Check-in not allowed: participant has no team assignment, userId=" + userId);
        }

        // 2. KST 기준 오늘 날짜
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));

        // 3. 기존 SUCCESS 레코드 있으면 멱등 반환
        Optional<ChallengeCheckIn> existing = checkInRepository
                .findByParticipantIdAndCheckInDate(participant.getId(), today);
        if (existing.isPresent() && existing.get().getStatus() == CheckInStatus.SUCCESS) {
            log.debug("CheckIn already SUCCESS, skipping: participantId={}", participant.getId());
            // 이미 SUCCESS면 참여율은 앞선 요청에서 반영됨 → 재계산 불필요.
            return new CheckInOutcome(CheckInResponse.from(existing.get()), null);
        }

        // 4. 체크인 레코드 생성 (PENDING → 판정 후 SUCCESS/FAILED로 갱신)
        ChallengeCheckIn checkIn;
        if (existing.isPresent()) {
            checkIn = existing.get();
        } else {
            checkIn = checkInInsertHelper.insertOrFetch(
                    ChallengeCheckIn.builder()
                            .participantId(participant.getId())
                            .challengeId(challengeId)
                            .teamId(participant.getTeamId())
                            .checkInDate(today)
                            .status(CheckInStatus.PENDING)
                            .build(),
                    participant.getId(),
                    today);
        }

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
            // 참여율 갱신은 이 트랜잭션이 커밋된 뒤(recordCheckIn) 별도 트랜잭션에서 낙관락 재시도로 수행한다.
            return new CheckInOutcome(CheckInResponse.from(saved), participant.getTeamId());
        }

        log.info("CheckIn FAILED (GPS): participantId={}, date={}", participant.getId(), today);
        return new CheckInOutcome(CheckInResponse.from(saved), null);
    }

    @Transactional(readOnly = true)
    public List<CheckInResponse> getTeamCheckIns(Long challengeId, LocalDate date) {
        return checkInRepository.findByChallengeIdAndCheckInDate(challengeId, date)
                .stream()
                .map(CheckInResponse::from)
                .collect(Collectors.toList());
    }

    /**
     * 낙관락 충돌 시 새 트랜잭션에서 Team을 re-read → 재계산 → 재저장을 재시도한다.
     * 각 시도가 REQUIRES_NEW로 커밋되므로, 충돌로 롤백돼도 다음 시도는 커밋된 최신 버전을 읽는다.
     */
    private void updateTeamParticipationRateWithRetry(Long teamId) {
        for (int attempt = 1; attempt <= PARTICIPATION_RATE_MAX_RETRIES; attempt++) {
            try {
                self().updateTeamParticipationRate(teamId);
                return;
            } catch (ObjectOptimisticLockingFailureException | OptimisticLockException e) {
                log.warn("팀 참여율 낙관락 충돌 재시도: teamId={}, attempt={}/{}",
                        teamId, attempt, PARTICIPATION_RATE_MAX_RETRIES);
            }
        }
        log.error("팀 참여율 갱신 재시도 소진(Lost Update 위험): teamId={}", teamId);
    }

    /**
     * 커밋된 체크인 기준으로 팀 참여율을 재계산·저장한다. 반드시 새 트랜잭션에서 수행하여
     * 커밋된 다른 인스턴스의 체크인·버전을 반영하고, 커밋 시 @Version으로 Lost Update를 감지한다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void updateTeamParticipationRate(Long teamId) {
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

    /** doRecordCheckIn 결과 홀더: 응답과, 커밋 후 참여율을 갱신할 팀 id(없으면 null). */
    public record CheckInOutcome(CheckInResponse response, Long teamIdToUpdate) {}
}
