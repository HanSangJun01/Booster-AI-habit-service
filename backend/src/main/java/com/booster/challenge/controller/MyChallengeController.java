package com.booster.challenge.controller;

import com.booster.challenge.dto.ChallengeResponse;
import com.booster.challenge.service.ChallengeService;
import com.booster.shared.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 내가 참여 중인 챌린지.
 *
 * <p>{@code GET /api/challenges} 는 <b>공개 챌린지 검색</b>이라 내 참여 여부와 무관하다.
 * 앱이 재시작 후에도 진행 중인 챌린지를 복원하려면 별도 조회가 필요하다.
 */
@RestController
@RequestMapping("/api/users/me/challenges")
@RequiredArgsConstructor
public class MyChallengeController {

    private final ChallengeService challengeService;

    @GetMapping
    public ApiResponse<List<ChallengeResponse>> myChallenges(@AuthenticationPrincipal Long userId) {
        return ApiResponse.success(challengeService.getMyChallenges(userId));
    }
}
