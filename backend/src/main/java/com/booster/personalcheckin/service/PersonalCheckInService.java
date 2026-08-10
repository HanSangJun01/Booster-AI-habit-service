package com.booster.personalcheckin.service;

import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
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
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import com.booster.coin.domain.CoinTransactionReason;
import com.booster.coin.service.CoinService;
import org.springframework.beans.factory.annotation.Value;

/**
 * 개인 GPS 인증 처리.
 *
 * <p>[주간 목표 모델] 인증은 <b>기록 · 스트릭 +1 · 마일스톤 보상</b>을 담당한다. 보상은 성취
 * 피드백이므로 인증하는 그 순간 지급한다.
 *
 * <p>반면 <b>목표 달성 판정과 스트릭 초기화는 하지 않는다</b> — 그건 주간 채점
 * ({@code WeeklyEvaluationService})의 몫이다. 과거 모델은 여기서 날짜 갭을 검사해 스트릭을
 * 리셋했고, 복귀 만료 경로에서도 리셋해 판단이 두 곳에 흩어져 있었다.
 *
 * <p>★불변식: PersonalCheckIn/Streak만 다루며 챌린지(B축) 흐름에 절대 쓰지 않는다.
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

    @Value("${booster.streak.reward-interval-days}")
    private int rewardIntervalDays;
    @Value("${booster.streak.reward-coins}")
    private long rewardCoins;

    @Transactional
    public CheckInResponse checkIn(Long userId, double currentLat, double currentLng) {
        LocalDate today = LocalDate.now(clock);

        // (BS-30 C1/C5/C#6) User 를 비관락으로 '먼저' 로드해 attendance/streak 갱신을 사용자 단위로
        // 직렬화하고, active 를 락 상태에서 확인한다(TOCTOU 차단). 주간 채점도 같은 락 순서
        // (User → Streak → Coin)를 쓰므로 데드락이 없다.
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.badRequest(
                        "LOCATION_NOT_REGISTERED", "개인 GPS 위치를 먼저 등록하세요."));

        // 당일 중복 인증 방지. 이 테이블에는 SUCCESS 만 저장되므로 레코드 존재 = 이미 인증 완료.
        if (personalCheckInRepository.existsByUserIdAndDate(userId, today)) {
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
        // (BS-30 C4) 첫 인증 동시요청 시 둘 다 존재하지 않음으로 판정 후 INSERT → 두 번째가
        // UNIQUE(user_id, date) 위반. IDENTITY 전략이라 save()에서 즉시 INSERT되어 여기서 잡히므로,
        // 원시 DataIntegrityViolationException(→500)이 아닌 409 충돌로 변환한다.
        try {
            personalCheckInRepository.save(PersonalCheckIn.success(userId, today, now));
        } catch (DataIntegrityViolationException e) {
            throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
        }

        user.increaseAttendance();

        Streak streak = streakRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
        streak.recordSuccess(today);

        // 마일스톤 보상은 인증하는 그 순간 지급한다(7·14·21…회마다 +100). 주 마감까지 미루면
        // 성취의 피드백이 최대 일주일 늦어져 동기부여가 죽는다.
        boolean rewardGranted = false;
        if (streak.isRewardMilestone(rewardIntervalDays)) {
            coinService.grant(userId, rewardCoins, CoinTransactionReason.STREAK_REWARD, null);
            rewardGranted = true;
        }

        return new CheckInResponse(today, PersonalCheckInStatus.SUCCESS, now,
                streak.getCurrentStreak(), streak.getMaxStreak(), user.getCoinBalance(), rewardGranted);
    }

    @Transactional(readOnly = true)
    public TodayStatusResponse getToday(Long userId) {
        LocalDate today = LocalDate.now(clock);
        return personalCheckInRepository.findByUserIdAndDate(userId, today)
                .map(c -> new TodayStatusResponse(today, c.getStatus().name(), c.getVerifiedAt()))
                .orElseGet(() -> new TodayStatusResponse(today, "NOT_CHECKED", null));
    }
}
