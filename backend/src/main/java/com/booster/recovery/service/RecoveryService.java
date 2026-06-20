package com.booster.recovery.service;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.domain.RecoveryStatus;
import com.booster.recovery.dto.RecoveryResultResponse;
import com.booster.recovery.dto.RecoveryStatusResponse;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.shared.common.BusinessException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 복귀 미션 흐름.
 * 성공: -50코인(클램핑), 스트릭 유지, totalAttendance +1, 미인증일 SUCCESS 보정.
 * 실패(스케줄러): -100코인(클램핑), 스트릭 0, 미인증일 FAILED.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RecoveryService {

    private final RecoveryMissionRepository recoveryMissionRepository;
    private final PersonalCheckInRepository personalCheckInRepository;
    private final PersonalLocationRepository personalLocationRepository;
    private final StreakRepository streakRepository;
    private final UserRepository userRepository;
    private final CoinService coinService;
    private final GpsVerificationEvaluator gpsEvaluator;
    private final Clock clock;

    @Value("${booster.coin.recovery-success-penalty}")
    private long successPenalty;
    @Value("${booster.coin.recovery-failure-penalty}")
    private long failurePenalty;

    @Transactional(readOnly = true)
    public RecoveryStatusResponse getStatus(Long userId) {
        return recoveryMissionRepository
                .findFirstByUserIdAndStatusOrderByDeadlineAtAsc(userId, RecoveryStatus.PENDING)
                .map(mission -> {
                    LocalDate missedDate = personalCheckInRepository.findById(mission.getPersonalCheckInId())
                            .map(PersonalCheckIn::getDate).orElse(null);
                    return new RecoveryStatusResponse(true, mission.getId(), missedDate, mission.getDeadlineAt());
                })
                .orElseGet(RecoveryStatusResponse::none);
    }

    /** 복귀 미션 GPS 인증 수행(성공 처리). */
    @Transactional
    public RecoveryResultResponse performRecovery(Long userId, double currentLat, double currentLng) {
        RecoveryMission mission = recoveryMissionRepository
                .findFirstByUserIdAndStatusOrderByDeadlineAtAsc(userId, RecoveryStatus.PENDING)
                .orElseThrow(() -> BusinessException.notFound(
                        "NO_RECOVERY_MISSION", "대기 중인 복귀 미션이 없습니다."));

        OffsetDateTime now = OffsetDateTime.now(clock);
        if (now.isAfter(mission.getDeadlineAt())) {
            throw BusinessException.badRequest("RECOVERY_EXPIRED", "복귀 미션 데드라인이 지났습니다.");
        }

        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));
        boolean within = gpsEvaluator.isWithinRadius(
                location.getLat(), location.getLng(), location.getRadiusMeters(),
                currentLat, currentLng);
        if (!within) {
            throw BusinessException.badRequest("GPS_OUT_OF_RANGE", "등록된 위치 반경을 벗어났습니다.");
        }

        // 1) 미션 완료
        mission.complete(now);

        // 2) 미인증일 PersonalCheckIn → SUCCESS 보정
        PersonalCheckIn missed = personalCheckInRepository.findById(mission.getPersonalCheckInId())
                .orElseThrow(() -> BusinessException.notFound(
                        "CHECK_IN_NOT_FOUND", "복귀 대상 체크인을 찾을 수 없습니다."));
        missed.markSuccess(now);

        // 3) 코인 차감(-50, 클램핑)
        long charged = coinService.charge(userId, successPenalty,
                CoinTransactionReason.RECOVERY_SUCCESS, mission.getId());

        // 4) 출석 +1
        User user = userRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        user.increaseAttendance();

        // 5) 스트릭 유지(증가 없음), lastSuccessDate = 수행일
        Streak streak = streakRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
        streak.keepAlive(LocalDate.now(clock));

        return new RecoveryResultResponse(mission.getId(), mission.getStatus(),
                mission.getCompletedAt(), streak.getCurrentStreak(), user.getCoinBalance(), charged);
    }

    /**
     * 스케줄러 ① 단계: 데드라인 초과 PENDING 미션 일괄 실패 처리.
     * @return 처리 건수
     */
    @Transactional
    public int expireOverdueMissions() {
        OffsetDateTime now = OffsetDateTime.now(clock);
        List<RecoveryMission> overdue = recoveryMissionRepository
                .findByStatusAndDeadlineAtLessThanEqual(RecoveryStatus.PENDING, now);

        for (RecoveryMission mission : overdue) {
            mission.fail();
            personalCheckInRepository.findById(mission.getPersonalCheckInId())
                    .ifPresent(PersonalCheckIn::markFailed);
            coinService.charge(mission.getUserId(), failurePenalty,
                    CoinTransactionReason.RECOVERY_FAILURE, mission.getId());
            streakRepository.findById(mission.getUserId()).ifPresent(Streak::reset);
        }
        if (!overdue.isEmpty()) {
            log.info("[RecoveryScheduler] expired {} overdue missions", overdue.size());
        }
        return overdue.size();
    }

    /**
     * 스케줄러 ② 단계: 어제(KST) 미인증 활성 사용자에 대해 RECOVERY_PENDING + 복귀 미션 생성.
     * 멱등: 재실행 시 어제 레코드가 이미 존재하므로 건너뛴다.
     * @return 생성 건수
     */
    @Transactional
    public int generatePendingForYesterday() {
        LocalDate today = LocalDate.now(clock);
        LocalDate yesterday = today.minusDays(1);
        OffsetDateTime deadline = today.atTime(23, 59, 59)
                .atZone(clock.getZone()).toOffsetDateTime();

        Set<Long> alreadyHasRecord = new HashSet<>(
                personalCheckInRepository.findUserIdsWithRecordOnDate(yesterday));

        int created = 0;
        for (User user : userRepository.findAllByActiveTrue()) {
            Long userId = user.getId();
            if (alreadyHasRecord.contains(userId)) {
                continue;
            }
            // 어제 이전에 가입한 사용자만 대상(가입일 당일/이후 미인증은 책임 없음)
            if (user.getJoinedAt().atZoneSameInstant(clock.getZone()).toLocalDate().isAfter(yesterday)) {
                continue;
            }
            PersonalCheckIn pending = personalCheckInRepository.save(
                    PersonalCheckIn.recoveryPending(userId, yesterday));
            recoveryMissionRepository.save(
                    RecoveryMission.createPending(userId, pending.getId(), deadline));
            created++;
        }
        if (created > 0) {
            log.info("[RecoveryScheduler] created {} recovery-pending records for {}", created, yesterday);
        }
        return created;
    }
}
