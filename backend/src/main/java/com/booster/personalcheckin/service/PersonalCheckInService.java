package com.booster.personalcheckin.service;

import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.dto.TodayStatusResponse;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.streak.domain.Streak;
import com.booster.streak.repository.StreakRepository;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
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

        OffsetDateTime now = OffsetDateTime.now(clock);
        if (existing != null) {
            existing.markSuccess(now); // RECOVERY_PENDING 등으로 이미 존재하던 당일 레코드 보정
        } else {
            personalCheckInRepository.save(PersonalCheckIn.success(userId, today, now));
        }

        Streak streak = streakRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
        streak.recordSuccess(today);

        User user = userRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        user.increaseAttendance();

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
