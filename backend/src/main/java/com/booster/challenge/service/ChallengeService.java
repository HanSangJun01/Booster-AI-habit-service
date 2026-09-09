package com.booster.challenge.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.dto.ChallengeDetailResponse;
import com.booster.challenge.dto.ChallengeResponse;
import com.booster.challenge.dto.CreateChallengeRequest;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.common.UnauthorizedException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.booster.challenge.domain.VerificationType;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import com.booster.participant.dto.ParticipationRequest;
import com.booster.participant.service.ParticipationService;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;

import java.util.EnumSet;
import java.util.List;
import java.util.Set;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChallengeService {

    private final ChallengeRepository challengeRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final PersonalLocationRepository personalLocationRepository;
    private final ParticipationService participationService;
    private final InviteCodeGenerator inviteCodeGenerator;
    private final UserRepository userRepository;

    /**
     * 체크인이 실제로 판정할 수 있는 인증 방식만 허용한다.
     *
     * <p>DB enum 에는 PHOTO / GPS_PHOTO 도 있지만 {@code ChallengeCheckInService} 는 GPS / AI /
     * GPS_PHOTO_AI 만 처리하고 나머지는 예외를 던진다. 생성 시점에 막지 않으면 <b>생성은 되는데
     * 아무도 체크인할 수 없는 좀비 챌린지</b>가 남는다(참가자 예치금까지 묶인 채로).
     *
     * <p>[2026-09 확정] 선택지를 "위치+사진" 하나로 좁혔다. 위치만·사진만은 각각 우회가 쉬워
     * (다른 사람 자리에서 체크인 / 예전 사진 재사용) 인증으로서 신뢰가 낮았다. 새 챌린지는
     * GPS_PHOTO_AI 만 만들 수 있다 — 기존 챌린지의 값은 건드리지 않는다.
     */
    private static final Set<VerificationType> SUPPORTED_VERIFICATION_TYPES =
            EnumSet.of(VerificationType.GPS_PHOTO_AI);

    @Transactional
    public ChallengeResponse createChallenge(Long userId, CreateChallengeRequest request) {
        if (!SUPPORTED_VERIFICATION_TYPES.contains(request.getVerificationType())) {
            throw BusinessException.badRequest("UNSUPPORTED_VERIFICATION_TYPE",
                    "인증 방식은 위치+사진(GPS_PHOTO_AI)만 지원합니다: " + request.getVerificationType());
        }

        Challenge challenge = Challenge.builder()
                .category(request.getCategory())
                .title(resolveTitle(userId, request))
                .description(request.getDescription())
                .verificationType(request.getVerificationType())
                .durationDays(request.getDurationDays())
                .depositCoins(request.getDepositCoins())
                .visibility(request.getVisibility())
                .approvalType(request.getApprovalType())
                .status(ChallengeStatus.READY)
                .maxParticipants(request.getMaxParticipants())
                .createdBy(userId)
                .build();

        if (request.getVisibility() == ChallengeVisibility.PRIVATE) {
            challenge.setInviteCode(inviteCodeGenerator.generate());
        }

        Challenge saved = challengeRepository.save(challenge);

        // 생성자를 곧바로 CONFIRMED 참가자로 등록한다(같은 트랜잭션 → 실패 시 챌린지도 롤백).
        participationService.registerCreatorAsParticipant(saved, userId, resolveCreatorGps(userId, request));

        log.info("Challenge created: id={}, userId={}, visibility={}", saved.getId(), userId, saved.getVisibility());
        return ChallengeResponse.from(saved);
    }

    /**
     * 챌린지 이름을 정한다.
     *
     * <p>앱이 더 이상 이름을 입력받지 않는다(카테고리만 고른다). 이름이 비어 오면
     * "운동 · 김부스터" 처럼 카테고리와 방장 닉네임으로 만들어, 목록에서 어느 방인지
     * 구분할 수 있게 한다. 예전 클라이언트가 이름을 보내오면 그대로 존중한다.
     */
    private String resolveTitle(Long userId, CreateChallengeRequest request) {
        String requested = request.getTitle();
        if (requested != null && !requested.isBlank()) {
            return requested;
        }
        String nickname = userRepository.findById(userId)
                .map(User::getNickname)
                .orElse("참가자");
        return categoryLabel(request.getCategory()) + " · " + nickname;
    }

    /** 목록에 보일 카테고리 이름. 저장값(EXERCISE/STUDY)은 그대로 두고 표시만 한글로 만든다. */
    private String categoryLabel(String category) {
        return "STUDY".equals(category) ? "공부" : "운동";
    }

    /**
     * 방장의 인증 기준 위치를 결정한다.
     * 요청에 좌표가 있으면 그것을, 없으면 개인 인증 위치를 재사용한다. 둘 다 없으면 거절한다.
     */
    private ParticipationRequest resolveCreatorGps(Long userId, CreateChallengeRequest request) {
        if (request.hasExplicitGps()) {
            return ParticipationRequest.of(request.getPersonalStatement(),
                    request.getGpsLat(), request.getGpsLng(),
                    request.getGpsRadiusMeters(), request.getGpsPlaceName());
        }
        return personalLocationRepository.findById(userId)
                .map(loc -> ParticipationRequest.of(request.getPersonalStatement(),
                        loc.getLat(), loc.getLng(), loc.getRadiusMeters(), loc.getPlaceName()))
                .orElseThrow(() -> BusinessException.badRequest("LOCATION_REQUIRED",
                        "인증 기준 위치가 필요합니다. 요청에 gpsLat/gpsLng/gpsRadiusMeters 를 넣거나 "
                                + "개인 인증 위치를 먼저 등록하세요."));
    }

    /**
     * 공개 챌린지 검색. 요청자의 참여 여부를 {@code joined} 로 함께 내려준다.
     * 참여 여부는 페이지당 쿼리 1회로 채운다(항목마다 조회하면 N+1).
     */
    public Page<ChallengeResponse> searchPublicChallenges(Long userId, String category,
                                                          String keyword, Pageable pageable) {
        Page<Challenge> page = challengeRepository.searchPublic(
                ChallengeStatus.READY, category, keyword, pageable);

        List<Long> ids = page.getContent().stream().map(Challenge::getId).toList();
        Set<Long> joinedIds = ids.isEmpty()
                ? Set.of()
                : Set.copyOf(participantRepository.findJoinedChallengeIds(userId, ids));

        return page.map(c -> ChallengeResponse.from(c, joinedIds.contains(c.getId())));
    }

    /**
     * 내가 참여 중인 챌린지 목록.
     *
     * <p>없을 때 앱은 참여 중인 챌린지를 메모리에만 들고 있어 재시작하면 잃어버렸고, 초대 코드나
     * 탐색으로 다시 찾아 들어가야 했다. 로컬에 저장하더라도 서버에서 취소·종료된 챌린지를 알 수
     * 없어 잘못된 상태를 보여주게 된다.
     */
    public List<ChallengeResponse> getMyChallenges(Long userId) {
        return participantRepository.findActiveByUserId(userId).stream()
                .map(p -> ChallengeResponse.from(p.getChallenge(), true))
                .toList();
    }

    public ChallengeDetailResponse getChallengeDetail(Long challengeId) {
        Challenge challenge = getOrThrow(challengeId);
        long confirmedCount = participantRepository.countByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);
        return ChallengeDetailResponse.from(challenge, confirmedCount);
    }

    public ChallengeResponse getChallengeByInviteCode(String code) {
        log.debug("Challenge lookup by invite code: {}", code);
        return challengeRepository.findByInviteCode(code)
                .map(ChallengeResponse::from)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge not found with invite code: " + code));
    }

    public Challenge getOrThrow(Long challengeId) {
        return challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));
    }

    /**
     * 방장이 자기 챌린지를 취소한다 — 참가자 전원에게 예치금을 돌려주고 방을 닫는다.
     *
     * <p>지금까지 만든 방을 없앨 방법이 아예 없어서, 잘못 만든 방이 목록에 계속 남았다.
     *
     * <p>모집 중(READY)일 때만 가능하다. 시작된 뒤에는 팀이 짜이고 체크인이 쌓이므로,
     * 방장 한 명의 판단으로 전부 무효로 만들 수 없다.
     */
    @Transactional
    public void cancelChallenge(Long userId, Long challengeId) {
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (!challenge.getCreatedBy().equals(userId)) {
            throw new UnauthorizedException("Only the challenge creator can cancel it");
        }

        if (!participationService.disbandReadyChallenge(challengeId)) {
            throw BusinessException.conflict("CHALLENGE_ALREADY_STARTED",
                    "이미 시작된 챌린지는 취소할 수 없습니다.");
        }
        log.info("Challenge cancelled by creator: challengeId={}, userId={}", challengeId, userId);
    }
}
