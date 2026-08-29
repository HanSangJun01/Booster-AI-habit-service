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
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.booster.challenge.domain.VerificationType;
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

    /**
     * 체크인이 실제로 판정할 수 있는 인증 방식만 허용한다.
     *
     * <p>DB enum 에는 PHOTO / GPS_PHOTO 도 있지만 {@code ChallengeCheckInService} 는 GPS / AI /
     * GPS_PHOTO_AI 만 처리하고 나머지는 예외를 던진다. 생성 시점에 막지 않으면 <b>생성은 되는데
     * 아무도 체크인할 수 없는 좀비 챌린지</b>가 남는다(참가자 예치금까지 묶인 채로).
     */
    private static final Set<VerificationType> SUPPORTED_VERIFICATION_TYPES =
            EnumSet.of(VerificationType.GPS, VerificationType.AI, VerificationType.GPS_PHOTO_AI);

    @Transactional
    public ChallengeResponse createChallenge(Long userId, CreateChallengeRequest request) {
        if (!SUPPORTED_VERIFICATION_TYPES.contains(request.getVerificationType())) {
            throw BusinessException.badRequest("UNSUPPORTED_VERIFICATION_TYPE",
                    "지원하지 않는 인증 방식입니다: " + request.getVerificationType()
                            + " (지원: GPS, AI, GPS_PHOTO_AI)");
        }

        Challenge challenge = Challenge.builder()
                .category(request.getCategory())
                .title(request.getTitle())
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
}
