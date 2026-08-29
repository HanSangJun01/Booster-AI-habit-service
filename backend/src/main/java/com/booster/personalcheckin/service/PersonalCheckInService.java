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

        // 당일 중복 방지. PENDING(사진 대기) 도 진행 중이므로 새 체크인을 만들지 않는다.
        personalCheckInRepository.findByUserIdAndDate(userId, today).ifPresent(existing -> {
            throw existing.isPending()
                    ? BusinessException.conflict("CHECK_IN_AWAITING_PHOTO",
                            "사진 인증이 남아 있습니다. 사진을 올려 완료해 주세요.")
                    : BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
        });

        // GPS 반경 판정 — 인증 방식이 GPS 를 요구할 때만. 실패 시 레코드를 만들지 않고 즉시 거절하고
        // 얼마나 벗어났는지까지 알려준다(팀 챌린지 체크인과 동일한 형식).
        if (location.needsGps()) {
            double distanceMeters = gpsEvaluator.calculateDistanceMeters(
                    location.getLat(), location.getLng(), currentLat, currentLng);
            if (distanceMeters > location.getRadiusMeters()) {
                throw BusinessException.badRequest("GPS_OUT_OF_RANGE",
                        String.format("등록된 위치에서 %.0fm 떨어져 있습니다. (허용 %dm)",
                                distanceMeters, location.getRadiusMeters()));
            }
        }

        OffsetDateTime now = OffsetDateTime.now(clock);

        // AI 를 쓰는 목표는 여기서 확정하지 않는다. PENDING 으로 만들어두고 사진이 올라오면
        // PersonalAiVerificationService 가 확정한다(스트릭·보상도 그때 처리).
        if (location.needsAi()) {
            PersonalCheckIn pending = savePending(userId, today);
            Streak streak = streakRepository.findById(userId)
                    .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
            return new CheckInResponse(today, PersonalCheckInStatus.PENDING, null,
                    streak.getCurrentStreak(), streak.getMaxStreak(), user.getCoinBalance(), false,
                    pending.getId());
        }

        // (BS-30 C4) 첫 인증 동시요청 시 둘 다 존재하지 않음으로 판정 후 INSERT → 두 번째가
        // UNIQUE(user_id, date) 위반. IDENTITY 전략이라 save()에서 즉시 INSERT되어 여기서 잡히므로,
        // 원시 DataIntegrityViolationException(→500)이 아닌 409 충돌로 변환한다.
        PersonalCheckIn saved;
        try {
            saved = personalCheckInRepository.save(PersonalCheckIn.success(userId, today, now));
        } catch (DataIntegrityViolationException e) {
            throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 완료했습니다.");
        }

        SuccessOutcome outcome = applySuccess(userId, user, today);
        return new CheckInResponse(today, PersonalCheckInStatus.SUCCESS, now,
                outcome.streak().getCurrentStreak(), outcome.streak().getMaxStreak(),
                user.getCoinBalance(), outcome.rewardGranted(), saved.getId());
    }

    /** 확정 처리 결과. 서비스는 싱글톤이므로 상태를 필드에 담지 않고 반환값으로 넘긴다. */
    public record SuccessOutcome(Streak streak, boolean rewardGranted) {}

    private PersonalCheckIn savePending(Long userId, LocalDate today) {
        try {
            return personalCheckInRepository.save(PersonalCheckIn.pending(userId, today));
        } catch (DataIntegrityViolationException e) {
            throw BusinessException.conflict("DUPLICATE_CHECK_IN", "오늘 이미 인증을 진행 중입니다.");
        }
    }

    /**
     * 출석·스트릭·마일스톤 보상 확정 — GPS 인증과 AI 인증이 공유한다.
     * (AI 는 사진이 통과한 시점에 {@code PersonalAiVerificationService} 가 호출한다)
     */
    public SuccessOutcome applySuccess(Long userId, User user, LocalDate date) {
        user.increaseAttendance();

        Streak streak = streakRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("STREAK_NOT_FOUND", "스트릭 정보가 없습니다."));
        streak.recordSuccess(date);

        // 마일스톤 보상은 인증이 확정되는 그 순간 지급한다(7·14·21…회마다 +100).
        boolean rewardGranted = false;
        if (streak.isRewardMilestone(rewardIntervalDays)) {
            coinService.grant(userId, rewardCoins, CoinTransactionReason.STREAK_REWARD, null);
            rewardGranted = true;
        }
        return new SuccessOutcome(streak, rewardGranted);
    }

    @Transactional(readOnly = true)
    public TodayStatusResponse getToday(Long userId) {
        LocalDate today = LocalDate.now(clock);
        return personalCheckInRepository.findByUserIdAndDate(userId, today)
                .map(c -> new TodayStatusResponse(today, c.getStatus().name(), c.getVerifiedAt()))
                .orElseGet(() -> new TodayStatusResponse(today, "NOT_CHECKED", null));
    }
}
