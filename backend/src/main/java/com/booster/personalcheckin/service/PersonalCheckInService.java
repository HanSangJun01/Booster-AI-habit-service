package com.booster.personalcheckin.service;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.dto.TodayStatusResponse;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.recovery.repository.RecoveryMissionRepository;
import com.booster.shared.common.BusinessException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 개인 GPS 인증 처리. 성공 시 스트릭 +1, 보상 마일스톤 시 코인 지급.
 * ★불변식: PersonalCheckIn/Streak/Coin만 다루며 챌린지(B축) 흐름에 절대 쓰지 않는다.
 */
@Service
@RequiredArgsConstructor
public class PersonalCheckInService {

    private final PersonalCheckInRepository personalCheckInRepository;
    private final PersonalLocationRepository personalLocationRepository;
    private final StreakRepository streakRepository;
    private final UserRepository userRepository;
    private final RecoveryMissionRepository recoveryMissionRepository;
    private final CoinService coinService;
    private final GpsVerificationEvaluator gpsEvaluator;
    private final Clock clock;

    @Value("${booster.streak.reward-repeat}")
    private boolean rewardRepeat;
    @Value("${booster.streak.reward-interval-days}")
    private int rewardIntervalDays;
    @Value("${booster.streak.reward-coins}")
    private long rewardCoins;

    @Transactional
    public CheckInResponse checkIn(Long userId, double currentLat, double currentLng) {
        LocalDate today = LocalDate.now(clock);

        // (BS-30 B3) 탈퇴(비활성) 계정 차단
        if (!userRepository.existsByIdAndActiveTrue(userId)) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        // (F2 팀 결정) 오늘이 복귀 대상일(오늘 마감인 복귀 미션 존재)이면 일반 인증 불가.
        // 복귀 수행이 곧 '오늘의 인증'으로 간주되므로 별도 인증을 막아 이중 카운트/순서 의존(F7)을 차단한다.
        OffsetDateTime dayStart = today.atStartOfDay(clock.getZone()).toOffsetDateTime();
        OffsetDateTime dayEnd = today.atTime(23, 59, 59).atZone(clock.getZone()).toOffsetDateTime();
        if (recoveryMissionRepository.existsByUserIdAndDeadlineAtBetween(userId, dayStart, dayEnd)) {
            throw BusinessException.conflict("RECOVERY_DAY_NO_CHECKIN",
                    "복귀 미션 대상일에는 복귀로 인증됩니다. 별도 일반 인증은 불가합니다.");
        }

        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));

        // 당일 중복 인증 방지 (이미 SUCCESS면 409)
        PersonalCheckIn existing = personalCheckInRepository
                .findByUserIdAndDate(userId, today).orElse(null);
        if (existing != null && existing.isSuccess()) {
            throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
        }

        // GPS 반경 판정 — 실패 시 레코드 생성하지 않음
        boolean within = gpsEvaluator.isWithinRadius(
                location.getLat(), location.getLng(), location.getRadiusMeters(),
                currentLat, currentLng);
        if (!within) {
            throw BusinessException.badRequest("GPS_OUT_OF_RANGE", "등록된 위치 반경을 벗어났습니다.");
        }

        // (BS-30 C1/C5) User 를 비관락으로 '먼저' 로드해 coin/attendance/streak 갱신을 사용자 단위로
        // 직렬화한다. 락 없이 findById 하면 보상 라운드에서 stale 잔액 위에 grant 를 얹어 동시 charge 를
        // 통째로 덮어쓰거나(C1), 동시 performRecovery 와 겹쳐 streak +1 이 소실된다(C5).
        // performRecovery 도 (mission→)User→Streak 순으로 락을 잡아 락 순서가 일치 → 데드락 없음.
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        // (BS-30 7차 C#6) 락 상태에서 active 재확인 → 초기 언락 가드 이후 탈퇴 커밋되는 TOCTOU 차단.
        if (!user.isActive()) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        OffsetDateTime now = OffsetDateTime.now(clock);
        if (existing != null) {
            existing.markSuccess(now); // RECOVERY_PENDING 등으로 이미 존재하던 당일 레코드 보정
        } else {
            // (BS-30 C4) 첫 인증 동시요청 시 둘 다 existing==null 판정 후 INSERT → 두 번째가
            // UNIQUE(user_id, date) 위반. IDENTITY 전략이라 save()에서 즉시 INSERT되어 여기서 잡히므로,
            // 원시 DataIntegrityViolationException(→500)이 아닌 409 충돌로 변환한다.
            try {
                personalCheckInRepository.save(PersonalCheckIn.success(userId, today, now));
            } catch (DataIntegrityViolationException e) {
                throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
            }
        }

        user.increaseAttendance();

        Streak streak = streakRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
        streak.recordSuccess(today);

        boolean rewardGranted = false;
        if (isRewardEligible(streak.getCurrentStreak())) {
            coinService.grant(userId, rewardCoins, CoinTransactionReason.STREAK_REWARD, null);
            rewardGranted = true;
        }

        return new CheckInResponse(today, com.booster.personalcheckin.domain.PersonalCheckInStatus.SUCCESS,
                now, streak.getCurrentStreak(), streak.getMaxStreak(), user.getCoinBalance(), rewardGranted);
    }

    /** 보상 지급 조건: 반복(%interval) 또는 최초 1회(== interval). */
    private boolean isRewardEligible(int currentStreak) {
        if (currentStreak <= 0) {
            return false;
        }
        if (rewardRepeat) {
            return currentStreak % rewardIntervalDays == 0;
        }
        return currentStreak == rewardIntervalDays;
    }

    @Transactional(readOnly = true)
    public TodayStatusResponse getToday(Long userId) {
        LocalDate today = LocalDate.now(clock);
        return personalCheckInRepository.findByUserIdAndDate(userId, today)
                .map(c -> new TodayStatusResponse(today, c.getStatus().name(), c.getVerifiedAt()))
                .orElseGet(() -> new TodayStatusResponse(today, "NOT_CHECKED", null));
    }
}
