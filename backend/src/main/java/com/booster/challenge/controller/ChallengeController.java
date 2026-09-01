package com.booster.challenge.controller;

import com.booster.challenge.dto.ChallengeDetailResponse;
import com.booster.challenge.dto.ChallengeResponse;
import com.booster.challenge.dto.CreateChallengeRequest;
import com.booster.challenge.service.ChallengeService;
import com.booster.shared.common.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ChallengeController {

    private final ChallengeService challengeService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ChallengeResponse> create(
            @AuthenticationPrincipal Long userId,
            @Valid @RequestBody CreateChallengeRequest request) {
        return ApiResponse.success(challengeService.createChallenge(userId, request));
    }

    @GetMapping("/{challengeId}")
    public ApiResponse<ChallengeDetailResponse> detail(@PathVariable Long challengeId) {
        return ApiResponse.success(challengeService.getChallengeDetail(challengeId));
    }

    /**
     * 방장이 자기 챌린지를 취소한다(참가자 전원 예치금 환불 + 방 닫기).
     *
     * <p>모집 중일 때만 가능하다. 시작된 챌린지는 409 로 거절한다.
     */
    @DeleteMapping("/{challengeId}")
    public ApiResponse<Void> cancel(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId) {
        challengeService.cancelChallenge(userId, challengeId);
        return ApiResponse.success(null);
    }

    @GetMapping
    public ApiResponse<Page<ChallengeResponse>> search(
            @AuthenticationPrincipal Long userId,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String keyword,
            Pageable pageable) {
        return ApiResponse.success(
                challengeService.searchPublicChallenges(userId, category, keyword, pageable));
    }

    @GetMapping("/invite/{code}")
    public ApiResponse<ChallengeResponse> findByCode(@PathVariable String code) {
        return ApiResponse.success(challengeService.getChallengeByInviteCode(code));
    }
}
