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
        // (BS-30 B3) 탈퇴(비활성) 계정 차단
        if (!userRepository.existsByIdAndActiveTrue(userId)) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        // (BS-30 C2) PENDING 미션을 비관락으로 획득 → 동시 수행 시 정확히 1회만 성공
        RecoveryMission mission = recoveryMissionRepository
                .findPendingByUserForUpdate(userId).stream().findFirst()
                .orElseThrow(() -> BusinessException.notFound(
                        "NO_RECOVERY_MISSION", "대기 중인 복귀 미션이 없습니다."));

        OffsetDateTime now = OffsetDateTime.now(clock);
        // (BS-30 C6) 경계 일치: 수행 조건은 "현재 < deadline"(strict). deadline==now 는 만료로 간주하여
        // 스케줄러(만료: deadline<=now)만 처리하게 한다 → 성공(-50)과 실패(-100) 이중차감 방지.
        if (!now.isBefore(mission.getDeadlineAt())) {
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

        // (BS-30 7차 C#6) User 를 비관락으로 로드하고 active 를 '락 상태에서' 재확인 → 초기 언락 가드와
        // 이 지점 사이에 탈퇴가 커밋되는 TOCTOU 를 닫는다(락으로 withdraw 와 직렬화).
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
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
        // (BS-30 C6/C7) 비관락으로 만료 대상 획득 → 스케줄러 중복 실행/수행 경계 충돌 시 이중 처리 방지.
        List<RecoveryMission> overdue = recoveryMissionRepository
                .findOverduePendingForUpdate(now);

        int processed = 0;
        for (RecoveryMission mission : overdue) {
            if (!mission.isPending()) {
                continue; // 락 획득 사이 다른 트랜잭션이 이미 처리 → 건너뜀(방어)
            }
            mission.fail();
            PersonalCheckIn missed = personalCheckInRepository.findById(mission.getPersonalCheckInId())
                    .orElse(null);
            if (missed != null) {
                missed.markFailed();
            }
            coinService.charge(mission.getUserId(), failurePenalty,
                    CoinTransactionReason.RECOVERY_FAILURE, mission.getId());
            // (BS-30 7차 F1) 미인증일 이후 유저가 이미 새 스트릭을 쌓았다면(lastSuccessDate > missedDate)
            // 그 스트릭을 만료 처리로 지우면 안 된다. 미인증일까지의 스트릭만 초기화한다.
            LocalDate missedDate = (missed != null) ? missed.getDate() : null;
            streakRepository.findById(mission.getUserId()).ifPresent(s -> {
                LocalDate last = s.getLastSuccessDate();
                if (last == null || missedDate == null || !last.isAfter(missedDate)) {
                    s.reset();
                }
            });
            processed++;
        }
        if (processed > 0) {
            log.info("[RecoveryScheduler] expired {} overdue missions", processed);
        }
        return processed;
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
            // (BS-30 B2) 어제 '이전'에 가입한 사용자만 대상. 가입일이 어제이거나 이후면 제외
            // (가입 당일 미인증은 책임 없음). 기존 isAfter(yesterday)는 가입일==어제를 포함하지 못하는 off-by-one.
            LocalDate joinedDate = user.getJoinedAt().atZoneSameInstant(clock.getZone()).toLocalDate();
            if (!joinedDate.isBefore(yesterday)) {
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
