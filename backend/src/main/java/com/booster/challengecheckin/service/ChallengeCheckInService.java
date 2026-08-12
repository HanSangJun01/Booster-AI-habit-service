package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.VerificationType;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.domain.DecisionStatus;
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
import com.booster.shared.common.UnauthorizedException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
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
import com.booster.shared.common.BusinessException;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional
public class ChallengeCheckInService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeRepository challengeRepository;
    private final TeamRepository teamRepository;
    private final GpsVerificationEvaluator gpsVerificationEvaluator;
    private final VerificationSubmissionRepository submissionRepository;
    private final GpsVerificationResultRepository gpsResultRepository;
    private final VerificationDecisionRepository decisionRepository;
    private final CheckInInsertHelper checkInInsertHelper;

    public CheckInResponse recordCheckIn(Long userId, Long challengeId, double submittedLat, double submittedLng) {
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
            throw BusinessException.conflict("CHALLENGE_NOT_ACTIVE", "진행 중인 챌린지에서만 인증할 수 있습니다.");
        }

        // 팀 배정 없는 참여자의 체크인 차단 — 정산 계산에서 누락되므로 허용 불가
        if (participant.getTeamId() == null) {
            throw BusinessException.conflict("TEAM_NOT_ASSIGNED",
                    "팀 배정이 완료되기 전에는 인증할 수 없습니다.");
        }

        // 2. KST 기준 오늘 날짜
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));

        // 3. 기존 SUCCESS 레코드 있으면 멱등 반환
        Optional<ChallengeCheckIn> existing = checkInRepository
                .findByParticipantIdAndCheckInDate(participant.getId(), today);
        if (existing.isPresent() && existing.get().getStatus() == CheckInStatus.SUCCESS) {
            log.debug("CheckIn already SUCCESS, skipping: participantId={}", participant.getId());
            return CheckInResponse.from(existing.get());
        }

        // 4. verification_type 스코프 검증 — GPS/AI/GPS_PHOTO_AI만 지원.
        VerificationType verificationType = challenge.getVerificationType();
        if (verificationType != VerificationType.GPS
                && verificationType != VerificationType.AI
                && verificationType != VerificationType.GPS_PHOTO_AI) {
            throw BusinessException.conflict("UNSUPPORTED_VERIFICATION_TYPE",
                    "지원하지 않는 인증 방식입니다: " + verificationType);
        }
        boolean needsGps = (verificationType == VerificationType.GPS
                || verificationType == VerificationType.GPS_PHOTO_AI);
        boolean needsAi = (verificationType == VerificationType.AI
                || verificationType == VerificationType.GPS_PHOTO_AI);

        // 5. GPS 판정을 '레코드 생성보다 먼저' 한다 — 개인 습관 인증과 동일한 순서.
        //
        // 예전에는 레코드를 PENDING 으로 먼저 만들고 판정 후 FAILED 로 갱신했다. 그 결과 실패해도
        // 200 + status=FAILED 가 나가서 클라이언트는 "왜 실패했는지"를 알 수 없었고, 사유를 보려면
        // 별도 조회 API 가 필요했다. 반면 개인 습관은 실패를 400 + 사유로 그 자리에서 알려준다.
        // 같은 GPS 인증인데 두 축의 동작이 달랐다 — 의도한 설계가 아니라 각자 만들어져서 생긴 차이다.
        //
        // FAILED 레코드는 참여율·정산에 쓰이지 않는다(ParticipationRateCalculator 는 SUCCESS 만 센다).
        // 그래서 남길 이유가 없고, 실패는 기록하지 않고 즉시 거절한다.
        double distanceMeters = 0;
        if (needsGps) {
            distanceMeters = gpsVerificationEvaluator.calculateDistanceMeters(
                    participant.getGpsLat(), participant.getGpsLng(), submittedLat, submittedLng);
            if (distanceMeters > participant.getGpsRadiusMeters()) {
                log.info("CheckIn rejected (GPS): participantId={}, distance={}m, radius={}m",
                        participant.getId(), Math.round(distanceMeters), participant.getGpsRadiusMeters());
                throw BusinessException.badRequest("GPS_OUT_OF_RANGE",
                        String.format("등록된 위치에서 %.0fm 떨어져 있습니다. (허용 %dm)",
                                distanceMeters, participant.getGpsRadiusMeters()));
            }
        }

        // 6. 체크인 레코드 생성 (GPS 를 통과했거나 GPS 판정이 없는 경우에만 도달한다)
        // (BS-39 I1) 삽입은 REQUIRES_NEW 헬퍼에서만 하고, UNIQUE 위반(같은 유저 동시 첫 체크인)은
        // 여기 — 오염되지 않은 바깥 트랜잭션 — 에서 잡아 재조회한다. 헬퍼 안에서 잡아 재조회하면
        // 오염된 세션이 flush되며 AssertionFailure(500)로 터진다.
        ChallengeCheckIn checkIn;
        if (existing.isPresent()) {
            checkIn = existing.get();
        } else {
            try {
                checkIn = checkInInsertHelper.insertInNewTransaction(
                        ChallengeCheckIn.builder()
                                .participantId(participant.getId())
                                .challengeId(challengeId)
                                .teamId(participant.getTeamId())
                                .checkInDate(today)
                                .status(CheckInStatus.PENDING)
                                .build());
            } catch (DataIntegrityViolationException e) {
                // 경쟁에서 짐 — 다른 요청이 먼저 오늘자 레코드를 넣었다. 바깥 세션에서 깨끗하게 재조회.
                checkIn = checkInRepository.findByParticipantIdAndCheckInDate(participant.getId(), today)
                        .orElseThrow(() -> BusinessException.conflict("CHECK_IN_CONFLICT",
                                "동시 요청 처리 중 충돌했습니다. 다시 시도해 주세요."));
                // 이미 SUCCESS로 확정된 레코드면 멱등 반환(동시 요청이 먼저 판정 완료한 경우).
                if (checkIn.getStatus() == CheckInStatus.SUCCESS) {
                    return CheckInResponse.from(checkIn);
                }
            }
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

        // 7. GPS 판정 결과 기록 (여기 도달했다는 건 반경 안이라는 뜻 — 실패는 5번에서 이미 거절됐다)
        if (needsGps) {
            gpsResultRepository.save(
                    GpsVerificationResult.builder()
                            .submissionId(submission.getId())
                            .targetLat(participant.getGpsLat())
                            .targetLng(participant.getGpsLng())
                            .radiusMeters(participant.getGpsRadiusMeters())
                            .distanceMeters(BigDecimal.valueOf(distanceMeters).setScale(2, RoundingMode.HALF_UP))
                            .isWithinRadius(true)
                            .build());
        }

        // 8. VerificationDecision 저장
        //  - AI 결과가 필요하면 PENDING으로 유보, /ai-verification 콜에서 확정
        //  - GPS 단독이면 이 시점에 이미 통과가 확정이므로 CONFIRMED
        DecisionStatus decisionStatus = needsAi ? DecisionStatus.PENDING : DecisionStatus.CONFIRMED;
        decisionRepository.save(
                VerificationDecision.builder()
                        .submissionId(submission.getId())
                        .decisionStatus(decisionStatus)
                        .finalPassed(needsAi ? null : Boolean.TRUE)
                        .failureReason(null)
                        .build());

        // 9. ChallengeCheckIn 상태 갱신 — AI 대기면 PENDING, 아니면 SUCCESS
        boolean awaitingAi = (decisionStatus == DecisionStatus.PENDING);
        checkIn.updateStatus(
                awaitingAi ? CheckInStatus.PENDING : CheckInStatus.SUCCESS,
                awaitingAi ? null : LocalDateTime.now());
        ChallengeCheckIn saved = checkInRepository.save(checkIn);

        if (awaitingAi) {
            log.info("CheckIn PENDING (awaiting AI): participantId={}, submissionId={}",
                    participant.getId(), submission.getId());
        } else {
            log.info("CheckIn SUCCESS: participantId={}, date={}", participant.getId(), today);
            updateTeamParticipationRate(participant.getTeamId());
        }

        // submissionId 를 함께 반환한다 — AI 인증 2단계 호출의 입력이며, 이게 없으면
        // 클라이언트가 그 값을 얻을 경로가 아예 없다.
        return CheckInResponse.from(saved, submission.getId());
    }

    /**
     * AI 인증 콜에서 판정 결과를 받아 verification_decisions를 확정한다.
     * verification_type=AI면 GPS 무관, GPS_PHOTO_AI면 GPS AND AI 조건.
     */
    public void finalizeDecisionAfterAi(Long submissionId, boolean aiPassed) {
        VerificationSubmission submission = submissionRepository.findById(submissionId)
                .orElseThrow(() -> new ResourceNotFoundException("VerificationSubmission", submissionId));
        ChallengeCheckIn checkIn = checkInRepository.findById(submission.getCheckInId())
                .orElseThrow(() -> new ResourceNotFoundException("ChallengeCheckIn", submission.getCheckInId()));
        Challenge challenge = challengeRepository.findById(checkIn.getChallengeId())
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", checkIn.getChallengeId()));
        VerificationDecision decision = decisionRepository.findBySubmissionId(submissionId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "VerificationDecision for submissionId=" + submissionId));

        if (decision.getDecisionStatus() == DecisionStatus.CONFIRMED) {
            throw BusinessException.conflict("DECISION_ALREADY_CONFIRMED",
                    "이미 판정이 확정된 인증입니다.");
        }

        VerificationType vt = challenge.getVerificationType();
        boolean gpsPassed;
        if (vt == VerificationType.AI) {
            gpsPassed = true;
        } else if (vt == VerificationType.GPS_PHOTO_AI) {
            gpsPassed = gpsResultRepository.findBySubmissionId(submissionId)
                    .map(GpsVerificationResult::isWithinRadius)
                    .orElse(false);
        } else {
            // 호출부 계약 위반(AI를 쓰지 않는 챌린지에 AI 확정을 요청) — 클라이언트 오류가 아니라
            // 서버 내부 버그이므로 409가 아닌 500으로 드러낸다.
            throw new IllegalStateException(
                    "finalizeDecisionAfterAi called for non-AI type: " + vt);
        }

        boolean finalPassed = gpsPassed && aiPassed;
        String failureReason;
        if (finalPassed) {
            failureReason = null;
        } else if (!gpsPassed) {
            failureReason = "GPS_OUT_OF_RADIUS";
        } else {
            failureReason = "AI_REJECTED";
        }
        decision.confirm(finalPassed, failureReason);
        decisionRepository.save(decision);

        CheckInStatus finalStatus = finalPassed ? CheckInStatus.SUCCESS : CheckInStatus.FAILED;
        LocalDateTime verifiedAt = finalPassed ? LocalDateTime.now() : null;
        checkIn.updateStatus(finalStatus, verifiedAt);
        checkInRepository.save(checkIn);

        if (finalPassed && checkIn.getTeamId() != null) {
            updateTeamParticipationRate(checkIn.getTeamId());
        }

        log.info("Decision finalized after AI: submissionId={}, finalPassed={}, verificationType={}",
                submissionId, finalPassed, vt);
    }

    @Transactional(readOnly = true)
    public List<CheckInResponse> getTeamCheckIns(Long userId, Long challengeId, LocalDate date) {
        // (BS-39 I14) 멤버십 검사. 예전엔 컨트롤러에 @AuthenticationPrincipal도, 여기에 검사도 없어
        // 비참여자가 임의 challengeId로 남의 팀 체크인 현황을 통째로 조회할 수 있었다(I2 팀채팅 읽기와
        // 동일 계열). team-detail(getTeamComparison)과 같은 CONFIRMED 참여 게이트를 적용한다.
        participantRepository.findConfirmedByUserAndChallenge(challengeId, userId)
                .orElseThrow(() -> new UnauthorizedException("Not a participant of this challenge"));
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
