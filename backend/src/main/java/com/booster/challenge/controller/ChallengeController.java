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
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ChallengeController {

    private final ChallengeService challengeService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ChallengeResponse> create(
            @RequestHeader("X-User-Id") Long userId,
            @Valid @RequestBody CreateChallengeRequest request) {
        return ApiResponse.success(challengeService.createChallenge(userId, request));
    }

    @GetMapping("/{challengeId}")
    public ApiResponse<ChallengeDetailResponse> detail(@PathVariable Long challengeId) {
        return ApiResponse.success(challengeService.getChallengeDetail(challengeId));
    }

    @GetMapping
    public ApiResponse<Page<ChallengeResponse>> search(
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String keyword,
            Pageable pageable) {
        return ApiResponse.success(challengeService.searchPublicChallenges(category, keyword, pageable));
    }

    @GetMapping("/invite/{code}")
    public ApiResponse<ChallengeResponse> findByCode(@PathVariable String code) {
        return ApiResponse.success(challengeService.getChallengeByInviteCode(code));
    }
}
